package recorder

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

const selectionTimeout = 5 * time.Minute

// PrepareSelection opens the portal picker before a recording begins, so the
// countdown runs against an already chosen window instead of the picker showing
// up once the countdown reaches zero. gpu-screen-recorder can only open the
// picker as part of a capture, so this starts a throwaway capture, waits for its
// first frame (which means the user picked something), and stops it again. The
// portal hands out a restore token on the way out; the real recording reuses it
// and starts straight away.
func (r *Recorder) PrepareSelection() (State, error) {
	r.mu.Lock()

	if r.cmd != nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrAlreadyRecording
	}
	if r.selectCmd != nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, ErrAlreadySelecting
	}
	if !r.firstFrameSupport {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, errors.New("this gpu-screen-recorder build cannot pre-select a capture source")
	}

	tokenPath := portalTokenPath()
	if err := os.MkdirAll(filepath.Dir(tokenPath), 0o700); err != nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, fmt.Errorf("prepare portal token directory: %w", err)
	}
	if err := os.Remove(tokenPath); err != nil && !errors.Is(err, os.ErrNotExist) {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, fmt.Errorf("clear the previous portal session: %w", err)
	}

	output := selectionOutputPath()
	_ = os.Remove(output)
	_ = os.Remove(firstFrameStampPath(output))

	cmd := exec.Command(r.binary,
		"-w", CapturePortal,
		"-f", "30",
		"-k", "h264",
		"-q", "medium",
		"-cursor", "no",
		"-restore-portal-session", "yes",
		"-portal-session-token-filepath", tokenPath,
		"-write-first-frame-ts", "yes",
		"-o", output,
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, fmt.Errorf("open the capture picker: %w", err)
	}

	r.selectCmd = cmd
	r.selectionReady = false
	r.selectionCancelled = false
	r.lastError = ""
	state := r.stateLocked(time.Now())
	listener := r.stateListener
	r.mu.Unlock()

	go r.watchSelection(cmd, output)
	notify(listener, state)
	return state, nil
}

// CancelSelection closes a picker that is still open.
func (r *Recorder) CancelSelection() (State, error) {
	r.mu.Lock()
	cmd := r.selectCmd
	if cmd == nil {
		r.selectionReady = false
		state := r.stateLocked(time.Now())
		r.mu.Unlock()
		return state, nil
	}
	r.selectionCancelled = true
	pid := cmd.Process.Pid
	state := r.stateLocked(time.Now())
	r.mu.Unlock()

	_ = signalProcessGroup(pid, syscall.SIGINT)
	return state, nil
}

// ClearSelection drops a prepared selection so the next recording picks again.
func (r *Recorder) ClearSelection() {
	r.mu.Lock()
	r.selectionReady = false
	r.mu.Unlock()
}

func (r *Recorder) watchSelection(cmd *exec.Cmd, output string) {
	exited := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		close(exited)
	}()

	stampPath := firstFrameStampPath(output)
	ticker := time.NewTicker(firstFramePollInterval)
	defer ticker.Stop()
	deadline := time.NewTimer(selectionTimeout)
	defer deadline.Stop()

	picked := false
	timedOut := false

watch:
	for {
		select {
		case <-exited:
			break watch
		case <-deadline.C:
			timedOut = true
			_ = signalProcessGroup(cmd.Process.Pid, syscall.SIGINT)
			waitOrKill(cmd, exited)
			break watch
		case <-ticker.C:
			if _, ok := readFirstFrameStamp(stampPath); !ok {
				continue
			}
			picked = true
			_ = signalProcessGroup(cmd.Process.Pid, syscall.SIGINT)
			waitOrKill(cmd, exited)
			break watch
		}
	}

	_ = os.Remove(output)
	_ = os.Remove(stampPath)

	r.mu.Lock()
	if r.selectCmd != cmd {
		r.mu.Unlock()
		return
	}
	cancelled := r.selectionCancelled
	r.selectCmd = nil
	r.selectionCancelled = false
	r.selectionReady = picked
	switch {
	case picked:
		r.lastError = ""
	case cancelled:
		r.lastError = ""
	case timedOut:
		r.lastError = "the capture picker timed out"
	default:
		r.lastError = "no capture source was chosen"
	}
	state := r.stateLocked(time.Now())
	listener := r.stateListener
	r.mu.Unlock()
	notify(listener, state)
}

func waitOrKill(cmd *exec.Cmd, exited <-chan struct{}) {
	select {
	case <-exited:
	case <-time.After(4 * time.Second):
		_ = signalProcessGroup(cmd.Process.Pid, syscall.SIGKILL)
		<-exited
	}
}

func portalTokenPath() string {
	if directory := os.Getenv("XDG_RUNTIME_DIR"); directory != "" {
		return filepath.Join(directory, "remcorder", "portal-token")
	}
	return filepath.Join(os.TempDir(), fmt.Sprintf("remcorder-%d", os.Getuid()), "portal-token")
}

func selectionOutputPath() string {
	return filepath.Join(os.TempDir(), fmt.Sprintf("remcorder-selection-%d.mp4", os.Getpid()))
}
