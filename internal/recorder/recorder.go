package recorder

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	CaptureRegion = "region"
	CapturePortal = "portal"
)

const firstFramePollInterval = 100 * time.Millisecond

var regionPattern = regexp.MustCompile(`^\d+x\d+\+-?\d+\+-?\d+$`)

var (
	ErrAlreadyRecording = errors.New("a recording is already active")
	ErrNotRecording     = errors.New("no recording is active")
	ErrAlreadyPaused    = errors.New("the recording is already paused")
	ErrNotPaused        = errors.New("the recording is not paused")
	ErrAlreadySelecting = errors.New("a capture picker is already open")
	ErrSelectionAborted = errors.New("the capture selection was cancelled")
	ErrNothingToRename  = errors.New("there is no finished recording to rename")
)

type Config struct {
	OutputDirectory      string
	Capture              string
	Region               string
	FPS                  int
	Audio                string
	Codec                string
	Quality              string
	Cursor               bool
	RestorePortalSession bool
	Keystrokes           bool
	KeystrokeHold        float64
}

type StartOptions struct {
	OutputDirectory      string   `json:"output_directory,omitempty"`
	Capture              string   `json:"capture,omitempty"`
	Region               string   `json:"region,omitempty"`
	FPS                  int      `json:"fps,omitempty"`
	Audio                *string  `json:"audio,omitempty"`
	Codec                string   `json:"codec,omitempty"`
	Quality              string   `json:"quality,omitempty"`
	Cursor               *bool    `json:"cursor,omitempty"`
	RestorePortalSession *bool    `json:"restore_portal_session,omitempty"`
	Keystrokes           *bool    `json:"keystrokes,omitempty"`
	KeystrokeHold        *float64 `json:"keystroke_hold,omitempty"`
}

type State struct {
	Recording          bool    `json:"recording"`
	Paused             bool    `json:"paused"`
	StartedAt          string  `json:"started_at,omitempty"`
	ObservedAt         string  `json:"observed_at"`
	DurationSeconds    int64   `json:"duration_seconds"`
	OutputFile         string  `json:"output_file,omitempty"`
	LastOutputFile     string  `json:"last_output_file,omitempty"`
	PID                int     `json:"pid,omitempty"`
	LastError          string  `json:"last_error,omitempty"`
	AwaitingFirstFrame bool    `json:"awaiting_first_frame"`
	Keystrokes         bool    `json:"keystrokes"`
	KeystrokeHold      float64 `json:"keystroke_hold,omitempty"`
	Selecting          bool    `json:"selecting"`
	SelectionReady     bool    `json:"selection_ready"`
}

type Recorder struct {
	mu                 sync.Mutex
	config             Config
	binary             string
	firstFrameSupport  bool
	cmd                *exec.Cmd
	done               chan struct{}
	startedAt          time.Time
	awaitingFirstFrame bool
	output             string
	paused             bool
	pausedAt           time.Time
	pausedFor          time.Duration
	lastOutput         string
	lastError          string
	stopping           bool
	discarding         bool
	keystrokes         bool
	keystrokeHold      float64
	stderr             bytes.Buffer
	stateListener      func(State)
	selectCmd          *exec.Cmd
	selectionReady     bool
	selectionCancelled bool
}

func New(config Config) (*Recorder, error) {
	if err := validateConfig(config); err != nil {
		return nil, err
	}

	binary, err := exec.LookPath("gpu-screen-recorder")
	if err != nil {
		return nil, errors.New("gpu-screen-recorder was not found in PATH")
	}
	return &Recorder{config: config, binary: binary, firstFrameSupport: supportsFirstFrameTimestamp(binary)}, nil
}

func supportsFirstFrameTimestamp(binary string) bool {
	output, _ := exec.Command(binary, "--help").CombinedOutput()
	return strings.Contains(string(output), "-write-first-frame-ts")
}

func (r *Recorder) Start() (State, error) {
	return r.StartWithOptions(StartOptions{})
}

func (r *Recorder) StartWithOptions(options StartOptions) (State, error) {
	r.mu.Lock()

	if r.cmd != nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrAlreadyRecording
	}
	config := applyOptions(r.config, options)
	if err := validateConfig(config); err != nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, err
	}
	if err := os.MkdirAll(config.OutputDirectory, 0o755); err != nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, fmt.Errorf("create output directory: %w", err)
	}

	now := time.Now()
	output := filepath.Join(config.OutputDirectory, now.Format("2006-01-02_15-04-05.000")+".mp4")
	args := []string{
		"-w", config.Capture,
		"-f", strconv.Itoa(config.FPS),
		"-k", config.Codec,
		"-q", config.Quality,
		"-cursor", yesNo(config.Cursor),
	}
	if config.Capture == CaptureRegion {
		args = append(args, "-region", strings.TrimSpace(config.Region))
	}
	if config.Capture == CapturePortal {
		args = append(args,
			"-restore-portal-session", yesNo(config.RestorePortalSession),
			"-portal-session-token-filepath", portalTokenPath())
	}
	if r.firstFrameSupport {
		args = append(args, "-write-first-frame-ts", "yes")
	}
	if strings.TrimSpace(config.Audio) != "" {
		args = append(args, "-a", config.Audio)
	}
	args = append(args, "-o", output)

	r.stderr.Reset()
	cmd := exec.Command(r.binary, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = &r.stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		r.lastError = err.Error()
		state := r.stateLocked(now)
		r.mu.Unlock()
		return state, fmt.Errorf("start gpu-screen-recorder: %w", err)
	}

	r.cmd = cmd
	r.done = make(chan struct{})
	r.startedAt = now
	r.awaitingFirstFrame = r.firstFrameSupport
	r.output = output
	r.keystrokes = config.Keystrokes
	r.keystrokeHold = config.KeystrokeHold
	r.lastError = ""
	r.stopping = false
	r.paused = false
	r.pausedAt = time.Time{}
	r.pausedFor = 0
	r.selectionReady = false
	done := r.done
	go r.wait(cmd, done, output)
	if r.firstFrameSupport {
		go r.watchFirstFrame(cmd, done, firstFrameStampPath(output))
	}

	state := r.stateLocked(now)
	listener := r.stateListener
	r.mu.Unlock()
	notify(listener, state)
	return state, nil
}

func validateConfig(config Config) error {
	if strings.TrimSpace(config.OutputDirectory) == "" {
		return errors.New("output directory must not be empty")
	}
	if strings.TrimSpace(config.Capture) == "" {
		return errors.New("capture source must not be empty")
	}
	if config.FPS < 1 || config.FPS > 1000 {
		return fmt.Errorf("fps must be between 1 and 1000, got %d", config.FPS)
	}
	if strings.TrimSpace(config.Codec) == "" {
		return errors.New("codec must not be empty")
	}
	if strings.TrimSpace(config.Quality) == "" {
		return errors.New("quality must not be empty")
	}
	if config.Capture == CaptureRegion {
		region := strings.TrimSpace(config.Region)
		if region == "" {
			return errors.New("region capture needs a region; drag one first")
		}
		if !regionPattern.MatchString(region) {
			return fmt.Errorf("region must look like WxH+X+Y, got %q", region)
		}
	}
	return nil
}

func applyOptions(config Config, options StartOptions) Config {
	if options.OutputDirectory != "" {
		config.OutputDirectory = options.OutputDirectory
	}
	if options.Capture != "" {
		config.Capture = options.Capture
	}
	if options.Region != "" {
		config.Region = options.Region
	}
	if options.FPS != 0 {
		config.FPS = options.FPS
	}
	if options.Audio != nil {
		config.Audio = *options.Audio
	}
	if options.Codec != "" {
		config.Codec = options.Codec
	}
	if options.Quality != "" {
		config.Quality = options.Quality
	}
	if options.Cursor != nil {
		config.Cursor = *options.Cursor
	}
	if options.RestorePortalSession != nil {
		config.RestorePortalSession = *options.RestorePortalSession
	}
	if options.Keystrokes != nil {
		config.Keystrokes = *options.Keystrokes
	}
	if options.KeystrokeHold != nil && *options.KeystrokeHold > 0 {
		config.KeystrokeHold = *options.KeystrokeHold
	}
	return config
}

func (r *Recorder) Pause() (State, error) {
	r.mu.Lock()
	if r.cmd == nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrNotRecording
	}
	if r.paused {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrAlreadyPaused
	}

	now := time.Now()
	if err := signalProcessGroup(r.cmd.Process.Pid, syscall.SIGUSR2); err != nil {
		state := r.stateLocked(now)
		r.mu.Unlock()
		return state, fmt.Errorf("pause recorder: %w", err)
	}
	r.paused = true
	r.pausedAt = now
	state := r.stateLocked(now)
	listener := r.stateListener
	r.mu.Unlock()
	notify(listener, state)
	return state, nil
}

func (r *Recorder) Resume() (State, error) {
	r.mu.Lock()
	if r.cmd == nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrNotRecording
	}
	if !r.paused {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrNotPaused
	}

	now := time.Now()
	if err := signalProcessGroup(r.cmd.Process.Pid, syscall.SIGUSR2); err != nil {
		state := r.stateLocked(now)
		r.mu.Unlock()
		return state, fmt.Errorf("resume recorder: %w", err)
	}
	r.pausedFor += now.Sub(r.pausedAt)
	r.paused = false
	r.pausedAt = time.Time{}
	state := r.stateLocked(now)
	listener := r.stateListener
	r.mu.Unlock()
	notify(listener, state)
	return state, nil
}

func (r *Recorder) Stop(ctx context.Context) (State, error) {
	return r.finish(ctx, false)
}

// Discard stops the recording and deletes its file instead of keeping it.
func (r *Recorder) Discard(ctx context.Context) (State, error) {
	return r.finish(ctx, true)
}

func (r *Recorder) finish(ctx context.Context, discard bool) (State, error) {
	r.mu.Lock()
	if r.cmd == nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrNotRecording
	}
	cmd := r.cmd
	done := r.done
	if discard {
		r.discarding = true
	}
	if !r.stopping {
		r.stopping = true
		if err := signalProcessGroup(cmd.Process.Pid, syscall.SIGINT); err != nil {
			r.stopping = false
			state := r.stateLocked(time.Now())
			r.mu.Unlock()
			return state, fmt.Errorf("ask recorder to finalize: %w", err)
		}
	}
	r.mu.Unlock()

	select {
	case <-done:
		r.mu.Lock()
		state := r.stateLocked(time.Now())
		errText := r.lastError
		r.mu.Unlock()
		if errText != "" {
			return state, errors.New(errText)
		}
		return state, nil
	case <-ctx.Done():
		_ = signalProcessGroup(cmd.Process.Pid, syscall.SIGKILL)
		return r.State(), fmt.Errorf("timed out finalizing recording: %w", ctx.Err())
	}
}

// Rename moves the last finished recording. A bare name stays in the same folder
// and keeps the original extension when none is given, so callers can pass the
// text a user typed straight through.
func (r *Recorder) Rename(target string) (State, error) {
	r.mu.Lock()
	if r.lastOutput == "" {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrNothingToRename
	}
	destination, err := resolveRenameTarget(r.lastOutput, target)
	if err == nil && destination != r.lastOutput {
		if _, statErr := os.Stat(destination); statErr == nil {
			err = fmt.Errorf("%s already exists", filepath.Base(destination))
		} else if renameErr := os.Rename(r.lastOutput, destination); renameErr != nil {
			err = fmt.Errorf("rename recording: %w", renameErr)
		} else {
			r.lastOutput = destination
		}
	}
	state := r.stateLocked(time.Now())
	listener := r.stateListener
	r.mu.Unlock()
	if err != nil {
		return state, err
	}
	notify(listener, state)
	return state, nil
}

func resolveRenameTarget(current, target string) (string, error) {
	target = strings.TrimSpace(target)
	if target == "" {
		return "", errors.New("the new name must not be empty")
	}
	if target == "." || target == ".." {
		return "", fmt.Errorf("%q is not a valid file name", target)
	}
	if !strings.ContainsRune(target, filepath.Separator) {
		target = filepath.Join(filepath.Dir(current), target)
	}
	if filepath.Ext(target) == "" {
		target += filepath.Ext(current)
	}
	return filepath.Clean(target), nil
}

// SetKeystrokes switches keystroke publishing for the running recording.
func (r *Recorder) SetKeystrokes(enabled bool, holdSeconds float64) State {
	r.mu.Lock()
	r.keystrokes = enabled
	if holdSeconds > 0 {
		r.keystrokeHold = holdSeconds
	}
	state := r.stateLocked(time.Now())
	listener := r.stateListener
	r.mu.Unlock()
	notify(listener, state)
	return state
}

func (r *Recorder) State() State {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.stateLocked(time.Now())
}

func (r *Recorder) SetStateListener(listener func(State)) {
	r.mu.Lock()
	r.stateListener = listener
	state := r.stateLocked(time.Now())
	r.mu.Unlock()
	notify(listener, state)
}

// watchFirstFrame keeps the clock honest when gpu-screen-recorder spends time in
// a picker or portal handshake before it captures anything: the elapsed time only
// starts at the timestamp of the frame that actually made it into the file.
func (r *Recorder) watchFirstFrame(cmd *exec.Cmd, done chan struct{}, stampPath string) {
	ticker := time.NewTicker(firstFramePollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-done:
			return
		case <-ticker.C:
			stamp, ok := readFirstFrameStamp(stampPath)
			if !ok {
				continue
			}
			_ = os.Remove(stampPath)

			r.mu.Lock()
			if r.cmd != cmd {
				r.mu.Unlock()
				return
			}
			r.startedAt = stamp
			r.awaitingFirstFrame = false
			state := r.stateLocked(time.Now())
			listener := r.stateListener
			r.mu.Unlock()
			notify(listener, state)
			return
		}
	}
}

func firstFrameStampPath(output string) string {
	return output + ".ts"
}

func readFirstFrameStamp(path string) (time.Time, bool) {
	data, err := os.ReadFile(path)
	if err != nil || len(data) == 0 {
		return time.Time{}, false
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) < 2 {
		return time.Time{}, false
	}
	fields := strings.Fields(lines[len(lines)-1])
	if len(fields) < 2 {
		return time.Time{}, false
	}
	microseconds, err := strconv.ParseInt(fields[1], 10, 64)
	if err != nil || microseconds <= 0 {
		return time.Now(), true
	}
	return time.UnixMicro(microseconds), true
}

func (r *Recorder) wait(cmd *exec.Cmd, done chan struct{}, output string) {
	err := cmd.Wait()

	r.mu.Lock()
	if r.cmd != cmd {
		r.mu.Unlock()
		close(done)
		return
	}

	wasStopping := r.stopping
	discarded := r.discarding
	r.cmd = nil
	r.done = nil
	r.stopping = false
	r.discarding = false
	r.output = ""
	r.awaitingFirstFrame = false
	_ = os.Remove(firstFrameStampPath(output))
	r.paused = false
	r.pausedAt = time.Time{}
	r.pausedFor = 0
	if discarded {
		_ = os.Remove(output)
	} else if fileInfo, statErr := os.Stat(output); statErr == nil && fileInfo.Size() > 0 {
		r.lastOutput = output
	}
	if err != nil && !wasStopping {
		detail := strings.TrimSpace(r.stderr.String())
		if detail != "" {
			r.lastError = fmt.Sprintf("gpu-screen-recorder exited: %v: %s", err, detail)
		} else {
			r.lastError = fmt.Sprintf("gpu-screen-recorder exited: %v", err)
		}
	} else if err != nil {
		r.lastError = fmt.Sprintf("gpu-screen-recorder could not finalize cleanly: %v", err)
	} else {
		r.lastError = ""
	}
	state := r.stateLocked(time.Now())
	listener := r.stateListener
	r.mu.Unlock()
	notify(listener, state)
	close(done)
}

func (r *Recorder) stateLocked(now time.Time) State {
	state := State{
		Recording:          r.cmd != nil,
		Paused:             r.cmd != nil && r.paused,
		ObservedAt:         now.Format(time.RFC3339Nano),
		LastOutputFile:     r.lastOutput,
		LastError:          r.lastError,
		AwaitingFirstFrame: r.cmd != nil && r.awaitingFirstFrame,
		Keystrokes:         r.cmd != nil && r.keystrokes,
		KeystrokeHold:      r.keystrokeHold,
		Selecting:          r.selectCmd != nil,
		SelectionReady:     r.selectionReady,
	}
	if r.cmd != nil {
		pausedFor := r.pausedFor
		if r.paused {
			pausedFor += now.Sub(r.pausedAt)
		}
		state.StartedAt = r.startedAt.Format(time.RFC3339)
		state.OutputFile = r.output
		state.PID = r.cmd.Process.Pid
		if !r.awaitingFirstFrame {
			state.DurationSeconds = max(0, int64((now.Sub(r.startedAt)-pausedFor)/time.Second))
		}
	}
	return state
}

func signalProcessGroup(pid int, signal syscall.Signal) error {
	err := syscall.Kill(-pid, signal)
	if errors.Is(err, syscall.ESRCH) {
		return nil
	}
	return err
}

func yesNo(value bool) string {
	if value {
		return "yes"
	}
	return "no"
}

func notify(listener func(State), state State) {
	if listener != nil {
		listener(state)
	}
}
