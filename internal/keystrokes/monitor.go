package keystrokes

import (
	"sync"
	"time"
)

const (
	// clearGrace keeps the row in the published snapshot slightly longer than
	// its hold time so the overlay has something to fade out.
	clearGrace = time.Second

	defaultHold      = 2500 * time.Millisecond
	defaultMaxTokens = 12
)

type Config struct {
	Hold      time.Duration
	MaxTokens int
}

func (config Config) withDefaults() Config {
	if config.Hold <= 0 {
		config.Hold = defaultHold
	}
	if config.MaxTokens <= 0 {
		config.MaxTokens = defaultMaxTokens
	}
	return config
}

// Monitor reads the keyboards directly so that it keeps working regardless of
// which window holds focus, which is the only option under Wayland.
type Monitor struct {
	config  Config
	publish func(Snapshot)

	mu     sync.Mutex
	stop   chan struct{}
	done   chan struct{}
	lastID int64
}

func NewMonitor(config Config, publish func(Snapshot)) *Monitor {
	return &Monitor{config: config.withDefaults(), publish: publish}
}

// SetHold changes how long a row stays up; it applies to the next Start.
func (m *Monitor) SetHold(hold time.Duration) {
	if hold <= 0 {
		return
	}
	m.mu.Lock()
	m.config.Hold = hold
	m.mu.Unlock()
}

func (m *Monitor) Running() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.stop != nil
}

func (m *Monitor) Start() error {
	m.mu.Lock()
	if m.stop != nil {
		m.mu.Unlock()
		return nil
	}

	devices, err := DiscoverKeyboards()
	if err == nil && len(devices) == 0 {
		err = errNoKeyboards
	}
	var set *deviceSet
	if err == nil {
		set, err = openDevices(devices)
	}
	if err != nil {
		m.mu.Unlock()
		m.emit(Snapshot{HoldSeconds: m.config.Hold.Seconds(), Error: err.Error()})
		return err
	}

	stop := make(chan struct{})
	done := make(chan struct{})
	m.stop, m.done = stop, done
	config := m.config
	lastID := m.lastID
	m.mu.Unlock()

	go m.run(config, set, lastID, stop, done)
	return nil
}

func (m *Monitor) Stop() {
	m.mu.Lock()
	stop, done := m.stop, m.done
	m.stop, m.done = nil, nil
	m.mu.Unlock()

	if stop == nil {
		return
	}
	close(stop)
	<-done
}

func (m *Monitor) run(config Config, set *deviceSet, lastID int64, stop <-chan struct{}, done chan<- struct{}) {
	defer close(done)
	defer set.close()

	current := newFolderFrom(config.MaxTokens, lastID)
	defer func() {
		m.mu.Lock()
		m.lastID = current.nextID
		m.mu.Unlock()
	}()
	buffer := make([]byte, readBufSize)

	var (
		lastCode   uint16
		lastValue  int32
		lastDevice = -1
		lastAt     time.Time
	)

	m.emit(current.snapshot(config.Hold))
	for {
		select {
		case <-stop:
			m.emit(Snapshot{HoldSeconds: config.Hold.Seconds(), Available: true, UpdatedAt: time.Now().UTC().Format(time.RFC3339Nano)})
			return
		default:
		}

		ready, err := set.selectReady()
		if err != nil {
			m.emit(Snapshot{HoldSeconds: config.Hold.Seconds(), Error: err.Error()})
			return
		}

		changed := false
		for _, index := range ready {
			events, readErr := readEvents(set.descriptors[index], buffer)
			if readErr != nil {
				continue
			}
			for _, event := range events {
				if event.Type != evKey {
					continue
				}
				now := time.Now()
				duplicate := index != lastDevice &&
					event.Code == lastCode &&
					event.Value == lastValue &&
					now.Sub(lastAt) < duplicateWindow
				lastCode, lastValue, lastDevice, lastAt = event.Code, event.Value, index, now
				if duplicate {
					continue
				}
				if current.apply(event.Code, event.Value, now) {
					changed = true
				}
			}
		}

		if current.expired(time.Now(), config.Hold+clearGrace) {
			current.clear()
			changed = true
		}
		if changed {
			m.emit(current.snapshot(config.Hold))
		}
	}
}

func (m *Monitor) emit(snapshot Snapshot) {
	if m.publish == nil {
		return
	}
	if snapshot.Tokens == nil {
		snapshot.Tokens = []Token{}
	}
	m.publish(snapshot)
}
