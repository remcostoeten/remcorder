package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/remcostoeten/recorder/internal/control"
)

func main() {
	defaultSocket, err := control.DefaultSocketPath()
	if err != nil {
		exitError(err)
	}

	socketPath := flag.String("socket", defaultSocket, "path to the daemon Unix socket")
	asJSON := flag.Bool("json", false, "print the complete response as JSON")
	timeout := flag.Duration("timeout", 15*time.Second, "maximum time to wait for the daemon")
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

	response, err := control.Call(*socketPath, control.Request{Action: action}, *timeout)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			exitError(fmt.Errorf("recorder daemon is not running (socket %s is missing)", *socketPath))
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

	if !response.OK {
		os.Exit(1)
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
	fmt.Fprintln(os.Stderr, "recorderctl:", err)
	os.Exit(1)
}
