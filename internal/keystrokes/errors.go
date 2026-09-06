package keystrokes

import "errors"

var errNoKeyboards = errors.New("no keyboard devices found in /proc/bus/input/devices")
