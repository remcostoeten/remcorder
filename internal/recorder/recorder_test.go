package recorder

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRecordingLifecycleFinalizesOutput(t *testing.T) {
	tempDirectory := t.TempDir()
	binary := writeFakeRecorder(t, tempDirectory, `
output=""
for argument in "$@"; do output="$argument"; done
trap 'printf "finalized" > "$output"; exit 0' INT
trap ':' USR2
while true; do sleep 0.05; done
`)
	engine := testRecorder(tempDirectory, binary)

	started, err := engine.Start()
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	if !started.Recording || started.PID == 0 || started.OutputFile == "" {
		t.Fatalf("Start() state = %#v", started)
	}

	// Give the shell enough time to install its signal handler.
	time.Sleep(100 * time.Millisecond)
	paused, err := engine.Pause()
	if err != nil {
		t.Fatalf("Pause() error = %v", err)
	}
	if !paused.Recording || !paused.Paused {
		t.Fatalf("Pause() state = %#v", paused)
	}
	time.Sleep(50 * time.Millisecond)
	resumed, err := engine.Resume()
	if err != nil {
		t.Fatalf("Resume() error = %v", err)
	}
	if !resumed.Recording || resumed.Paused {
		t.Fatalf("Resume() state = %#v", resumed)
	}
	time.Sleep(50 * time.Millisecond)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	stopped, err := engine.Stop(ctx)
	if err != nil {
		t.Fatalf("Stop() error = %v", err)
	}
	if stopped.Recording {
		t.Fatalf("Stop() state = %#v, want idle", stopped)
	}
	if stopped.LastOutputFile != started.OutputFile {
		t.Fatalf("LastOutputFile = %q, want %q", stopped.LastOutputFile, started.OutputFile)
	}
	data, err := os.ReadFile(stopped.LastOutputFile)
	if err != nil {
		t.Fatalf("read finalized output: %v", err)
	}
	if string(data) != "finalized" {
		t.Fatalf("output = %q, want finalized", data)
	}
}

func TestDiscardRemovesOutput(t *testing.T) {
	tempDirectory := t.TempDir()
	binary := writeFakeRecorder(t, tempDirectory, `
output=""
for argument in "$@"; do output="$argument"; done
printf "partial" > "$output"
trap 'printf "finalized" > "$output"; exit 0' INT
while true; do sleep 0.05; done
`)
	engine := testRecorder(tempDirectory, binary)

	started, err := engine.Start()
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	time.Sleep(100 * time.Millisecond)

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	discarded, err := engine.Discard(ctx)
	if err != nil {
		t.Fatalf("Discard() error = %v", err)
	}
	if discarded.Recording {
		t.Fatalf("Discard() state = %#v, want idle", discarded)
	}
	if discarded.LastOutputFile != "" {
		t.Fatalf("LastOutputFile = %q, want empty after discard", discarded.LastOutputFile)
	}
	if _, statErr := os.Stat(started.OutputFile); !os.IsNotExist(statErr) {
		t.Fatalf("output %q still exists after discard (stat err = %v)", started.OutputFile, statErr)
	}
}

func TestDurationExcludesPausedTime(t *testing.T) {
	now := time.Now()
	engine := &Recorder{
		cmd:       &exec.Cmd{Process: &os.Process{Pid: 123}},
		startedAt: now.Add(-10 * time.Second),
		paused:    true,
		pausedAt:  now.Add(-2 * time.Second),
		pausedFor: 3 * time.Second,
	}

	state := engine.stateLocked(now)
	if state.DurationSeconds != 5 {
		t.Fatalf("DurationSeconds = %d, want 5", state.DurationSeconds)
	}
	if !state.Paused {
		t.Fatal("Paused = false, want true")
	}
}

func TestApplyStartOptions(t *testing.T) {
	audio := ""
	cursor := false
	base := Config{
		OutputDirectory: "/base",
		Capture:         "screen",
		FPS:             60,
		Audio:           "default_output",
		Codec:           "h264",
		Quality:         "very_high",
		Cursor:          true,
	}
	got := applyOptions(base, StartOptions{
		OutputDirectory: "/chosen",
		Capture:         "portal",
		FPS:             30,
		Audio:           &audio,
		Codec:           "hevc",
		Quality:         "high",
		Cursor:          &cursor,
	})

	if got.OutputDirectory != "/chosen" || got.Capture != "portal" || got.FPS != 30 {
		t.Fatalf("capture options not applied: %#v", got)
	}
	if got.Audio != "" || got.Codec != "hevc" || got.Quality != "high" || got.Cursor {
		t.Fatalf("encoding options not applied: %#v", got)
	}
}

func TestUnexpectedExitIsReported(t *testing.T) {
	tempDirectory := t.TempDir()
	binary := writeFakeRecorder(t, tempDirectory, `
echo "capture source unavailable" >&2
exit 7
`)
	engine := testRecorder(tempDirectory, binary)

	if _, err := engine.Start(); err != nil {
		t.Fatalf("Start() error = %v", err)
	}

	deadline := time.Now().Add(2 * time.Second)
	for engine.State().Recording && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	state := engine.State()
	if state.Recording {
		t.Fatal("recorder did not notice child exit")
	}
	if !strings.Contains(state.LastError, "capture source unavailable") {
		t.Fatalf("LastError = %q", state.LastError)
	}
}

func testRecorder(outputDirectory, binary string) *Recorder {
	return &Recorder{
		config: Config{
			OutputDirectory: outputDirectory,
			Capture:         "screen",
			FPS:             60,
			Codec:           "h264",
			Quality:         "very_high",
			Cursor:          true,
		},
		binary: binary,
	}
}

func TestRegionCaptureForwardsTheRegionArgument(t *testing.T) {
	tempDirectory := t.TempDir()
	argumentsPath := filepath.Join(tempDirectory, "arguments")
	binary := writeFakeRecorder(t, tempDirectory, `
output=""
for argument in "$@"; do output="$argument"; done
printf '%s\n' "$@" > "`+argumentsPath+`"
trap 'printf "finalized" > "$output"; exit 0' INT
while true; do sleep 0.05; done
`)
	engine := testRecorder(tempDirectory, binary)

	if _, err := engine.StartWithOptions(StartOptions{Capture: "region", Region: "800x600+120+40"}); err != nil {
		t.Fatalf("StartWithOptions() error = %v", err)
	}
	// Give the shell enough time to install its signal handler.
	time.Sleep(150 * time.Millisecond)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if _, err := engine.Stop(ctx); err != nil {
		t.Fatalf("Stop() error = %v", err)
	}

	arguments, err := os.ReadFile(argumentsPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(arguments), "-region\n800x600+120+40\n") {
		t.Fatalf("arguments = %q, want -region 800x600+120+40", arguments)
	}
	if !strings.Contains(string(arguments), "-w\nregion\n") {
		t.Fatalf("arguments = %q, want -w region", arguments)
	}
}

func TestRegionCaptureRejectsAMissingOrMalformedRegion(t *testing.T) {
	tempDirectory := t.TempDir()
	binary := writeFakeRecorder(t, tempDirectory, "sleep 5\n")
	engine := testRecorder(tempDirectory, binary)

	for _, region := range []string{"", "not-a-region", "800x600", "800x600+120"} {
		if _, err := engine.StartWithOptions(StartOptions{Capture: "region", Region: region}); err == nil {
			t.Fatalf("StartWithOptions(region=%q) error = nil, want a validation error", region)
		}
	}
}

func writeFakeRecorder(t *testing.T, directory, body string) string {
	t.Helper()
	path := filepath.Join(directory, "fake-gpu-screen-recorder")
	script := "#!/bin/sh\n" + body
	if err := os.WriteFile(path, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRenameMovesTheLastOutput(t *testing.T) {
	tempDirectory := t.TempDir()
	binary := writeFakeRecorder(t, tempDirectory, `
output=""
for argument in "$@"; do output="$argument"; done
trap 'printf "finalized" > "$output"; exit 0' INT
while true; do sleep 0.05; done
`)
	engine := testRecorder(tempDirectory, binary)

	if _, err := engine.Rename("nothing"); !errors.Is(err, ErrNothingToRename) {
		t.Fatalf("Rename() before any recording error = %v, want ErrNothingToRename", err)
	}

	started, err := engine.Start()
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}
	time.Sleep(100 * time.Millisecond)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if _, err := engine.Stop(ctx); err != nil {
		t.Fatalf("Stop() error = %v", err)
	}

	renamed, err := engine.Rename("demo clip")
	if err != nil {
		t.Fatalf("Rename() error = %v", err)
	}
	want := filepath.Join(filepath.Dir(started.OutputFile), "demo clip"+filepath.Ext(started.OutputFile))
	if renamed.LastOutputFile != want {
		t.Fatalf("LastOutputFile = %q, want %q", renamed.LastOutputFile, want)
	}
	if _, err := os.Stat(started.OutputFile); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("original file still present: %v", err)
	}
	data, err := os.ReadFile(want)
	if err != nil || string(data) != "finalized" {
		t.Fatalf("renamed file = %q, %v", data, err)
	}

	if err := os.WriteFile(filepath.Join(tempDirectory, "taken.mp4"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := engine.Rename("taken.mp4"); err == nil {
		t.Fatal("Rename() onto an existing file succeeded, want error")
	}
	if _, err := engine.Rename("   "); err == nil {
		t.Fatal("Rename() with an empty name succeeded, want error")
	}
}
