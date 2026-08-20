package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/remcostoeten/remcorder/internal/control"
	"github.com/remcostoeten/remcorder/internal/recorder"
)

func main() {
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)

	defaultSocket, err := control.DefaultSocketPath()
	if err != nil {
		log.Fatal(err)
	}

	defaultOutput, err := defaultOutputDirectory()
	if err != nil {
		log.Fatal(err)
	}

	var (
		socketPath = flag.String("socket", defaultSocket, "path to the daemon Unix socket")
		outputDir  = flag.String("output-dir", defaultOutput, "directory in which recordings are saved")
		capture    = flag.String("capture", "screen", "gpu-screen-recorder capture source (screen, portal, monitor, or region)")
		region     = flag.String("region", "", "region to capture as WxH+X+Y when -capture is region")
		fps        = flag.Int("fps", 60, "maximum recording frame rate")
		audio      = flag.String("audio", "default_output", "audio source; empty disables audio")
		codec      = flag.String("codec", "h264", "video codec")
		quality    = flag.String("quality", "very_high", "recording quality")
		cursor     = flag.Bool("cursor", true, "include the pointer in recordings")
		stateFile  string
	)
	flag.StringVar(&stateFile, "state-file", "", "JSON state snapshot path (defaults beside the socket)")
	flag.Parse()
	if stateFile == "" {
		stateFile = filepath.Join(filepath.Dir(*socketPath), "state.json")
	}

	engine, err := recorder.New(recorder.Config{
		OutputDirectory: *outputDir,
		Capture:         *capture,
		Region:          *region,
		FPS:             *fps,
		Audio:           *audio,
		Codec:           *codec,
		Quality:         *quality,
		Cursor:          *cursor,
	})
	if err != nil {
		log.Fatal(err)
	}
	listener, err := listen(*socketPath)
	if err != nil {
		log.Fatal(err)
	}
	engine.SetStateListener(func(state recorder.State) {
		if err := publishState(stateFile, state); err != nil {
			log.Printf("publish state: %v", err)
		}
	})
	defer func() {
		_ = listener.Close()
		_ = os.Remove(*socketPath)
	}()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	var clients sync.WaitGroup
	go func() {
		<-ctx.Done()
		_ = listener.Close()

		stopCtx, stopCancel := context.WithTimeout(context.Background(), 12*time.Second)
		defer stopCancel()
		if _, err := engine.Stop(stopCtx); err != nil && !errors.Is(err, recorder.ErrNotRecording) {
			log.Printf("could not finalize active recording: %v", err)
		}
	}()

	log.Printf("ready on %s; recordings go to %s", *socketPath, *outputDir)
	for {
		conn, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				break
			}
			log.Printf("accept: %v", err)
			continue
		}

		clients.Add(1)
		go func() {
			defer clients.Done()
			handle(conn, engine)
		}()
	}
	clients.Wait()
}

func publishState(path string, state recorder.State) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, append(data, '\n'), 0o600); err != nil {
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	return nil
}

func listen(socketPath string) (net.Listener, error) {
	if err := os.MkdirAll(filepath.Dir(socketPath), 0o700); err != nil {
		return nil, fmt.Errorf("create socket directory: %w", err)
	}
	if err := os.Chmod(filepath.Dir(socketPath), 0o700); err != nil {
		return nil, fmt.Errorf("secure socket directory: %w", err)
	}

	if info, err := os.Lstat(socketPath); err == nil {
		if info.Mode()&os.ModeSocket == 0 {
			return nil, fmt.Errorf("refusing to remove non-socket path %s", socketPath)
		}
		conn, dialErr := net.DialTimeout("unix", socketPath, 200*time.Millisecond)
		if dialErr == nil {
			_ = conn.Close()
			return nil, fmt.Errorf("another recorder daemon is already listening on %s", socketPath)
		}
		if err := os.Remove(socketPath); err != nil {
			return nil, fmt.Errorf("remove stale socket: %w", err)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("inspect socket: %w", err)
	}

	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		return nil, fmt.Errorf("listen on %s: %w", socketPath, err)
	}
	if err := os.Chmod(socketPath, 0o600); err != nil {
		_ = listener.Close()
		return nil, fmt.Errorf("secure socket: %w", err)
	}
	return listener, nil
}

func handle(conn net.Conn, engine *recorder.Recorder) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(15 * time.Second))

	var request control.Request
	if err := json.NewDecoder(io.LimitReader(conn, 64<<10)).Decode(&request); err != nil {
		writeResponse(conn, control.Response{OK: false, Error: "invalid request: " + err.Error()})
		return
	}

	var (
		state recorder.State
		err   error
	)
	switch request.Action {
	case control.ActionStatus:
		state = engine.State()
	case control.ActionStart:
		state, err = engine.StartWithOptions(request.Options)
	case control.ActionStop:
		ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
		state, err = engine.Stop(ctx)
		cancel()
	case control.ActionToggle:
		if engine.State().Recording {
			ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
			state, err = engine.Stop(ctx)
			cancel()
		} else {
			state, err = engine.StartWithOptions(request.Options)
		}
	case control.ActionPause:
		state, err = engine.Pause()
	case control.ActionResume:
		state, err = engine.Resume()
	case control.ActionTogglePause:
		if engine.State().Paused {
			state, err = engine.Resume()
		} else {
			state, err = engine.Pause()
		}
	default:
		err = fmt.Errorf("unknown action %q", request.Action)
		state = engine.State()
	}

	response := control.Response{OK: err == nil, State: state}
	if err != nil {
		response.Error = err.Error()
	}
	writeResponse(conn, response)
}

func writeResponse(writer io.Writer, response control.Response) {
	if err := json.NewEncoder(writer).Encode(response); err != nil {
		log.Printf("write response: %v", err)
	}
}

func defaultOutputDirectory() (string, error) {
	if value := strings.TrimSpace(os.Getenv("REMCORDER_OUTPUT_DIR")); value != "" {
		return value, nil
	}
	if value := strings.TrimSpace(os.Getenv("XDG_VIDEOS_DIR")); value != "" {
		return filepath.Join(expandHome(strings.Trim(value, `"`)), "Recordings"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("find home directory: %w", err)
	}
	if data, readErr := os.ReadFile(filepath.Join(home, ".config", "user-dirs.dirs")); readErr == nil {
		for _, line := range strings.Split(string(data), "\n") {
			key, value, found := strings.Cut(line, "=")
			if found && strings.TrimSpace(key) == "XDG_VIDEOS_DIR" {
				return filepath.Join(expandHome(strings.Trim(strings.TrimSpace(value), `"`)), "Recordings"), nil
			}
		}
	}
	return filepath.Join(home, "Videos", "Recordings"), nil
}

func expandHome(path string) string {
	home, err := os.UserHomeDir()
	if err == nil {
		path = strings.Replace(path, "$HOME", home, 1)
	}
	return path
}
