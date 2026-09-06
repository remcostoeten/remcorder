package keystrokes

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const procInputDevices = "/proc/bus/input/devices"

type Device struct {
	Name string
	Path string
}

// DiscoverKeyboards lists the evdev nodes that can report ordinary typing.
//
// Keyboard-shaped nodes are identified by their EV_KEY capability bitmap rather
// than by name or by the by-path symlinks: peripherals routinely expose several
// "kbd" handlers, only some of which carry letter keys, and a keyboard may also
// expose a mouse node.
func DiscoverKeyboards() ([]Device, error) {
	file, err := os.Open(procInputDevices)
	if err != nil {
		return nil, fmt.Errorf("read input device list: %w", err)
	}
	defer file.Close()

	var (
		devices []Device
		name    string
		node    string
		typing  bool
	)
	flush := func() {
		if typing && node != "" {
			devices = append(devices, Device{Name: name, Path: filepath.Join("/dev/input", node)})
		}
		name, node, typing = "", "", false
	}

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			flush()
			continue
		}
		switch {
		case strings.HasPrefix(line, "N: Name="):
			name = strings.Trim(strings.TrimPrefix(line, "N: Name="), `"`)
		case strings.HasPrefix(line, "H: Handlers="):
			node = eventNode(strings.TrimPrefix(line, "H: Handlers="))
		case strings.HasPrefix(line, "B: KEY="):
			typing = hasTypingKeys(parseBitmap(strings.TrimPrefix(line, "B: KEY=")))
		}
	}
	flush()
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan input device list: %w", err)
	}
	return devices, nil
}

func eventNode(handlers string) string {
	for _, handler := range strings.Fields(handlers) {
		if strings.HasPrefix(handler, "event") {
			return handler
		}
	}
	return ""
}

// parseBitmap decodes the space separated hex words the kernel prints for a
// capability bitmap. The words run most significant first, so the final word
// holds bits 0 to 63.
func parseBitmap(value string) []uint64 {
	words := strings.Fields(value)
	bitmap := make([]uint64, len(words))
	for index, word := range words {
		parsed, err := strconv.ParseUint(word, 16, 64)
		if err != nil {
			continue
		}
		bitmap[len(words)-1-index] = parsed
	}
	return bitmap
}

func bitmapHas(bitmap []uint64, bit int) bool {
	word := bit / 64
	if word >= len(bitmap) {
		return false
	}
	return bitmap[word]&(1<<uint(bit%64)) != 0
}

func hasTypingKeys(bitmap []uint64) bool {
	for _, code := range [...]int{keyA, keyZ, keySpace, keyEnter} {
		if !bitmapHas(bitmap, code) {
			return false
		}
	}
	return true
}
