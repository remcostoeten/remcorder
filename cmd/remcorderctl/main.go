package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/remcostoeten/remcorder/internal/control"
)

func main() {
	defaultSocket, err := control.DefaultSocketPath()
	if err != nil {
		exitError(err)
	}

	socketPath := flag.String("socket", defaultSocket, "path to the daemon Unix socket")
	asJSON := flag.Bool("json", false, "print the complete response as JSON")
	timeout := flag.Duration("timeout", 15*time.Second, "maximum time to wait for the daemon")
	delay := flag.Duration("delay", 0, "wait this long before sending a start command")
	openFile := flag.Bool("open", false, "open the recording with the default application once it stops")
	openDir := flag.Bool("open-dir", false, "open the recording's folder once it stops")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "Usage: %s [options] <status|start|stop|toggle|pause|resume|toggle-pause>\n\n", os.Args[0])
		flag.PrintDefaults()
	}
	flag.Parse()

	action := control.ActionStatus
	if flag.NArg() > 1 {
		flag.Usage()
		os.Exit(2)
	}
	if flag.NArg() == 1 {
		action = control.Action(strings.ToLower(flag.Arg(0)))
	}
	if !action.Valid() {
		exitError(fmt.Errorf("unknown command %q (expected status, start, stop, toggle, pause, resume, or toggle-pause)", action))
	}

	if action == control.ActionStart && *delay > 0 {
		fmt.Printf("starting in %s…\n", delay.Round(time.Second))
		time.Sleep(*delay)
	}

	response, err := control.Call(*socketPath, control.Request{Action: action}, *timeout)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			exitError(fmt.Errorf("remcorder daemon is not running (socket %s is missing)", *socketPath))
		}
		exitError(err)
	}

	if *asJSON {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetIndent("", "  ")
		if err := encoder.Encode(response); err != nil {
			exitError(err)
		}
	} else {
		printHuman(response)
	}

	if (action == control.ActionStop || action == control.ActionToggle) &&
		response.OK && !response.State.Recording && response.State.LastOutputFile != "" {
		if *openFile {
			openPath(response.State.LastOutputFile)
		}
		if *openDir {
			openPath(filepath.Dir(response.State.LastOutputFile))
		}
	}

	if !response.OK {
		os.Exit(1)
	}
}

func openPath(path string) {
	if err := exec.Command("xdg-open", path).Start(); err != nil {
		fmt.Fprintln(os.Stderr, "remcorderctl: could not open", path+":", err)
	}
}

func printHuman(response control.Response) {
	if !response.OK {
		fmt.Fprintln(os.Stderr, "error:", response.Error)
		return
	}

	state := response.State
	if state.Recording {
		if state.Paused {
			fmt.Printf("paused %s", formatDuration(state.DurationSeconds))
		} else {
			fmt.Printf("recording %s", formatDuration(state.DurationSeconds))
		}
		if state.OutputFile != "" {
			fmt.Printf(" → %s", state.OutputFile)
		}
		fmt.Println()
		return
	}

	if state.LastOutputFile != "" {
		fmt.Printf("idle (last recording: %s)\n", state.LastOutputFile)
		return
	}
	fmt.Println("idle")
}

func formatDuration(seconds int64) string {
	duration := time.Duration(seconds) * time.Second
	hours := int(duration.Hours())
	minutes := int(duration.Minutes()) % 60
	secs := int(duration.Seconds()) % 60
	return fmt.Sprintf("%02d:%02d:%02d", hours, minutes, secs)
}

func exitError(err error) {
	fmt.Fprintln(os.Stderr, "remcorderctl:", err)
	os.Exit(1)
}
