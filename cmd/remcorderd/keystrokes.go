package main

import (
	"sync"

	"github.com/remcostoeten/remcorder/internal/keystrokes"
)

// keystrokeSwitch serializes monitor start/stop away from the recorder's state
// callback, which would otherwise wait on the reader loop's poll interval
// before a stop request could be answered.
type keystrokeSwitch struct {
	monitor *keystrokes.Monitor

	mu      sync.Mutex
	desired bool
	closed  bool

	signal chan struct{}
	done   chan struct{}
}

func newKeystrokeSwitch(monitor *keystrokes.Monitor, onError func(error)) *keystrokeSwitch {
	control := &keystrokeSwitch{
		monitor: monitor,
		signal:  make(chan struct{}, 1),
		done:    make(chan struct{}),
	}
	go control.run(onError)
	return control
}

func (k *keystrokeSwitch) set(active bool) {
	k.mu.Lock()
	if k.closed {
		k.mu.Unlock()
		return
	}
	k.desired = active
	k.mu.Unlock()

	select {
	case k.signal <- struct{}{}:
	default:
	}
}

func (k *keystrokeSwitch) run(onError func(error)) {
	defer close(k.done)
	for range k.signal {
		k.mu.Lock()
		active, closed := k.desired, k.closed
		k.mu.Unlock()

		switch {
		case closed:
			k.monitor.Stop()
			return
		case active:
			if err := k.monitor.Start(); err != nil && onError != nil {
				onError(err)
			}
		default:
			k.monitor.Stop()
		}
	}
}

func (k *keystrokeSwitch) close() {
	k.mu.Lock()
	if k.closed {
		k.mu.Unlock()
		return
	}
	k.closed = true
	k.mu.Unlock()

	select {
	case k.signal <- struct{}{}:
	default:
	}
	<-k.done
	close(k.signal)
}
