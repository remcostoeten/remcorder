package keystrokes

import (
	"strings"
	"time"
)

type Token struct {
	Text  string `json:"text"`
	Count int    `json:"count"`
	ID    int64  `json:"id"`
}

type Snapshot struct {
	Tokens      []Token `json:"tokens"`
	UpdatedAt   string  `json:"updated_at"`
	HoldSeconds float64 `json:"hold_seconds"`
	Available   bool    `json:"available"`
	Error       string  `json:"error,omitempty"`
}

// folder turns a stream of raw evdev key transitions into the chips the overlay
// draws: modifiers collapse into the chord they belong to, and a held key
// becomes a repeat count instead of a run of identical chips.
type folder struct {
	maxTokens int
	tokens    []Token
	nextID    int64
	held      map[uint16]bool
	lastAt    time.Time
}

func newFolder(maxTokens int) *folder {
	return newFolderFrom(maxTokens, 0)
}

// newFolderFrom continues numbering after lastID so that tokens published
// across a monitor restart (pause and resume) never reuse an ID the overlay
// has already seen and discarded.
func newFolderFrom(maxTokens int, lastID int64) *folder {
	if maxTokens < 1 {
		maxTokens = 1
	}
	return &folder{maxTokens: maxTokens, nextID: lastID, held: make(map[uint16]bool)}
}

func (f *folder) modifier(codes ...uint16) bool {
	for _, code := range codes {
		if f.held[code] {
			return true
		}
	}
	return false
}

// apply records one key transition and reports whether the visible row changed.
func (f *folder) apply(code uint16, value int32, at time.Time) bool {
	if isModifier(code) {
		switch value {
		case valueDown, valueRepeat:
			f.held[code] = true
		case valueUp:
			delete(f.held, code)
		}
		return false
	}
	if value != valueDown && value != valueRepeat {
		return false
	}

	text := f.render(code)
	if text == "" {
		return false
	}

	f.lastAt = at
	if last := len(f.tokens) - 1; last >= 0 && f.tokens[last].Text == text {
		f.tokens[last].Count++
		return true
	}

	f.nextID++
	f.tokens = append(f.tokens, Token{Text: text, Count: 1, ID: f.nextID})
	if len(f.tokens) > f.maxTokens {
		f.tokens = append([]Token(nil), f.tokens[len(f.tokens)-f.maxTokens:]...)
	}
	return true
}

func (f *folder) render(code uint16) string {
	shift := f.modifier(keyLeftShift, keyRightShift)
	ctrl := f.modifier(keyLeftCtrl, keyRightCtrl)
	alt := f.modifier(keyLeftAlt, keyRightAlt)
	meta := f.modifier(keyLeftMeta, keyRightMeta)

	if !ctrl && !alt && !meta {
		glyph := label(code, shift)
		if glyph == "" {
			return ""
		}
		if shift && namedKey(code) {
			return "Shift+" + glyph
		}
		return glyph
	}

	glyph := label(code, false)
	if glyph == "" {
		return ""
	}
	if len(glyph) == 1 && glyph[0] >= 'a' && glyph[0] <= 'z' {
		glyph = string(glyph[0] - 32)
	}

	parts := make([]string, 0, 5)
	if ctrl {
		parts = append(parts, "Ctrl")
	}
	if alt {
		parts = append(parts, "Alt")
	}
	if meta {
		parts = append(parts, "Super")
	}
	if shift {
		parts = append(parts, "Shift")
	}
	return strings.Join(append(parts, glyph), "+")
}

func (f *folder) expired(now time.Time, after time.Duration) bool {
	return len(f.tokens) > 0 && now.Sub(f.lastAt) > after
}

func (f *folder) clear() {
	f.tokens = nil
}

func (f *folder) snapshot(hold time.Duration) Snapshot {
	stamp := f.lastAt
	if stamp.IsZero() {
		stamp = time.Now()
	}
	return Snapshot{
		Tokens:      append([]Token(nil), f.tokens...),
		UpdatedAt:   stamp.UTC().Format(time.RFC3339Nano),
		HoldSeconds: hold.Seconds(),
		Available:   true,
	}
}
