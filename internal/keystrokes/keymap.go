package keystrokes

const (
	keyEsc        = 1
	keyBackspace  = 14
	keyTab        = 15
	keyEnter      = 28
	keyLeftCtrl   = 29
	keyA          = 30
	keyLeftShift  = 42
	keyZ          = 44
	keyRightShift = 54
	keyLeftAlt    = 56
	keySpace      = 57
	keyCapsLock   = 58
	keyKPEnter    = 96
	keyRightCtrl  = 97
	keyRightAlt   = 100
	keyLeftMeta   = 125
	keyRightMeta  = 126
)

// unshifted maps evdev key codes to the glyph or name shown on screen, assuming
// a US layout. evdev reports physical positions, so a Dvorak or AZERTY user
// sees the label of the key they pressed rather than the character it produced.
var unshifted = map[uint16]string{
	keyEsc: "Esc",
	2:      "1", 3: "2", 4: "3", 5: "4", 6: "5",
	7: "6", 8: "7", 9: "8", 10: "9", 11: "0",
	12: "-", 13: "=",
	keyBackspace: "Bksp",
	keyTab:       "Tab",
	16:           "q", 17: "w", 18: "e", 19: "r", 20: "t",
	21: "y", 22: "u", 23: "i", 24: "o", 25: "p",
	26: "[", 27: "]",
	keyEnter: "Enter",
	30:       "a", 31: "s", 32: "d", 33: "f", 34: "g",
	35: "h", 36: "j", 37: "k", 38: "l",
	39: ";", 40: "'", 41: "`", 43: "\\",
	44: "z", 45: "x", 46: "c", 47: "v", 48: "b", 49: "n", 50: "m",
	51: ",", 52: ".", 53: "/",
	55:          "KP*",
	keySpace:    "Space",
	keyCapsLock: "Caps",
	59:          "F1", 60: "F2", 61: "F3", 62: "F4", 63: "F5", 64: "F6",
	65: "F7", 66: "F8", 67: "F9", 68: "F10", 87: "F11", 88: "F12",
	69: "NumLk", 70: "ScrLk",
	71: "KP7", 72: "KP8", 73: "KP9", 74: "KP-",
	75: "KP4", 76: "KP5", 77: "KP6", 78: "KP+",
	79: "KP1", 80: "KP2", 81: "KP3", 82: "KP0", 83: "KP.",
	keyKPEnter: "Enter",
	98:         "KP/",
	99:         "SysRq",
	102:        "Home", 103: "Up", 104: "PgUp", 105: "Left",
	106: "Right", 107: "End", 108: "Down", 109: "PgDn",
	110: "Ins", 111: "Del", 119: "Pause", 127: "Menu",
}

var shifted = map[uint16]string{
	2: "!", 3: "@", 4: "#", 5: "$", 6: "%",
	7: "^", 8: "&", 9: "*", 10: "(", 11: ")",
	12: "_", 13: "+",
	26: "{", 27: "}",
	39: ":", 40: "\"", 41: "~", 43: "|",
	51: "<", 52: ">", 53: "?",
}

var modifierNames = map[uint16]string{
	keyLeftCtrl:   "Ctrl",
	keyRightCtrl:  "Ctrl",
	keyLeftShift:  "Shift",
	keyRightShift: "Shift",
	keyLeftAlt:    "Alt",
	keyRightAlt:   "Alt",
	keyLeftMeta:   "Super",
	keyRightMeta:  "Super",
}

func isModifier(code uint16) bool {
	_, found := modifierNames[code]
	return found
}

// label renders a key code for display. Shift is folded into the glyph itself
// so that a vim recording shows ":" and "D" rather than "Shift+;" and
// "Shift+d", which is how the viewer reads the command back.
func label(code uint16, shift bool) string {
	if shift {
		if glyph, found := shifted[code]; found {
			return glyph
		}
	}
	glyph, found := unshifted[code]
	if !found {
		return ""
	}
	if shift && len(glyph) == 1 && glyph[0] >= 'a' && glyph[0] <= 'z' {
		return string(glyph[0] - 32)
	}
	return glyph
}

// namedKey reports whether a label is a word such as "Enter" rather than a
// single printable glyph. Named keys keep an explicit "Shift+" prefix because
// there is no shifted glyph to fold into.
func namedKey(code uint16) bool {
	glyph, found := unshifted[code]
	return found && len([]rune(glyph)) > 1
}
