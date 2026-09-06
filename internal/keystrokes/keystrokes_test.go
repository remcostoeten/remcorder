package keystrokes

import (
	"testing"
	"time"
)

func TestHasTypingKeysAcceptsKeyboards(t *testing.T) {
	keyboard := "1000000000007 ff9f207ac14057ff febeffdfffefffff fffffffffffffffe"
	if !hasTypingKeys(parseBitmap(keyboard)) {
		t.Fatal("expected a keyboard bitmap to report typing keys")
	}
}

func TestHasTypingKeysRejectsPointers(t *testing.T) {
	mouse := "1f0000 0 0 0 0"
	if hasTypingKeys(parseBitmap(mouse)) {
		t.Fatal("expected a pointer bitmap to be rejected")
	}
}

func TestEventNodePrefersEventHandler(t *testing.T) {
	if node := eventNode("sysrq kbd leds event4 "); node != "event4" {
		t.Fatalf("got %q, want event4", node)
	}
}

func press(f *folder, at time.Time, codes ...uint16) {
	for _, code := range codes {
		f.apply(code, valueDown, at)
		f.apply(code, valueUp, at)
	}
}

func texts(f *folder) []string {
	rendered := make([]string, 0, len(f.tokens))
	for _, token := range f.tokens {
		rendered = append(rendered, token.Text)
	}
	return rendered
}

func equal(got, want []string) bool {
	if len(got) != len(want) {
		return false
	}
	for index := range got {
		if got[index] != want[index] {
			return false
		}
	}
	return true
}

func TestFolderRendersVimSequence(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	press(f, now, 46, 23, 17)

	if want := []string{"c", "i", "w"}; !equal(texts(f), want) {
		t.Fatalf("got %v, want %v", texts(f), want)
	}
}

func TestFolderFoldsShiftIntoGlyph(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	f.apply(keyLeftShift, valueDown, now)
	press(f, now, 39)
	f.apply(keyLeftShift, valueUp, now)
	press(f, now, 17, 16)

	if want := []string{":", "w", "q"}; !equal(texts(f), want) {
		t.Fatalf("got %v, want %v", texts(f), want)
	}
}

func TestFolderUppercasesShiftedLetters(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	f.apply(keyLeftShift, valueDown, now)
	press(f, now, 32)

	if want := []string{"D"}; !equal(texts(f), want) {
		t.Fatalf("got %v, want %v", texts(f), want)
	}
}

func TestFolderCollapsesRepeats(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	f.apply(36, valueDown, now)
	for range 4 {
		f.apply(36, valueRepeat, now)
	}

	if len(f.tokens) != 1 {
		t.Fatalf("got %d tokens, want 1", len(f.tokens))
	}
	if f.tokens[0].Count != 5 {
		t.Fatalf("got count %d, want 5", f.tokens[0].Count)
	}
}

func TestFolderRendersChords(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	f.apply(keyLeftCtrl, valueDown, now)
	press(f, now, 32)
	f.apply(keyLeftShift, valueDown, now)
	press(f, now, 47)

	if want := []string{"Ctrl+D", "Ctrl+Shift+V"}; !equal(texts(f), want) {
		t.Fatalf("got %v, want %v", texts(f), want)
	}
}

func TestFolderKeepsShiftPrefixForNamedKeys(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	f.apply(keyLeftShift, valueDown, now)
	press(f, now, keyTab)

	if want := []string{"Shift+Tab"}; !equal(texts(f), want) {
		t.Fatalf("got %v, want %v", texts(f), want)
	}
}

func TestFolderIgnoresLoneModifiers(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	f.apply(keyLeftCtrl, valueDown, now)
	f.apply(keyLeftCtrl, valueUp, now)

	if len(f.tokens) != 0 {
		t.Fatalf("got %d tokens, want 0", len(f.tokens))
	}
}

func TestFolderCapsRowLength(t *testing.T) {
	now := time.Now()
	f := newFolder(3)
	press(f, now, 30, 31, 32, 33, 34)

	if want := []string{"f", "g"}; !equal(texts(f)[1:], want) {
		t.Fatalf("got %v, want tail %v", texts(f), want)
	}
	if len(f.tokens) != 3 {
		t.Fatalf("got %d tokens, want 3", len(f.tokens))
	}
}

func TestFolderExpiresAfterHold(t *testing.T) {
	now := time.Now()
	f := newFolder(12)
	press(f, now, 30)

	if f.expired(now.Add(time.Second), 2*time.Second) {
		t.Fatal("row expired too early")
	}
	if !f.expired(now.Add(3*time.Second), 2*time.Second) {
		t.Fatal("row should have expired")
	}
}

func TestFolderContinuesIDsAcrossRestart(t *testing.T) {
	now := time.Now()
	first := newFolder(12)
	press(first, now, keyA, keyZ)

	second := newFolderFrom(12, first.nextID)
	press(second, now, keyA)

	if got := second.tokens[0].ID; got <= first.tokens[1].ID {
		t.Fatalf("restarted folder reused id %d; want greater than %d", got, first.tokens[1].ID)
	}
}
