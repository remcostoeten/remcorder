package control

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"

	"github.com/remcostoeten/remcorder/internal/recorder"
)

type Action string

const (
	ActionStatus      Action = "status"
	ActionStart       Action = "start"
	ActionStop        Action = "stop"
	ActionToggle      Action = "toggle"
	ActionPause       Action = "pause"
	ActionResume      Action = "resume"
	ActionTogglePause Action = "toggle-pause"
)

func (action Action) Valid() bool {
	switch action {
	case ActionStatus, ActionStart, ActionStop, ActionToggle, ActionPause, ActionResume, ActionTogglePause:
		return true
	default:
		return false
	}
}

type Request struct {
	Action  Action                `json:"action"`
	Options recorder.StartOptions `json:"options,omitempty"`
}

type Response struct {
	OK    bool           `json:"ok"`
	State recorder.State `json:"state"`
	Error string         `json:"error,omitempty"`
}

func DefaultSocketPath() (string, error) {
	if path := os.Getenv("RECORDER_SOCKET"); path != "" {
		return path, nil
	}
	if runtimeDirectory := os.Getenv("XDG_RUNTIME_DIR"); runtimeDirectory != "" {
		return filepath.Join(runtimeDirectory, "remcorder", "recorder.sock"), nil
	}
	return filepath.Join(os.TempDir(), fmt.Sprintf("remcorder-%d", os.Getuid()), "recorder.sock"), nil
}

func Call(socketPath string, request Request, timeout time.Duration) (Response, error) {
	conn, err := net.DialTimeout("unix", socketPath, timeout)
	if err != nil {
		return Response{}, err
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(timeout)); err != nil {
		return Response{}, fmt.Errorf("set daemon deadline: %w", err)
	}

	if err := json.NewEncoder(conn).Encode(request); err != nil {
		return Response{}, fmt.Errorf("send daemon request: %w", err)
	}

	var response Response
	if err := json.NewDecoder(conn).Decode(&response); err != nil {
		return Response{}, fmt.Errorf("read daemon response: %w", err)
	}
	if !response.OK && response.Error == "" {
		return Response{}, errors.New("daemon returned an unspecified error")
	}
	return response, nil
}
