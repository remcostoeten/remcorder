package keystrokes

import (
	"encoding/binary"
	"syscall"
	"testing"
)

func encodeEvent(kind, code uint16, value int32) []byte {
	chunk := make([]byte, eventSize)
	binary.LittleEndian.PutUint64(chunk[0:8], 1700000000)
	binary.LittleEndian.PutUint64(chunk[8:16], 250000)
	binary.LittleEndian.PutUint16(chunk[16:18], kind)
	binary.LittleEndian.PutUint16(chunk[18:20], code)
	binary.LittleEndian.PutUint32(chunk[20:24], uint32(value))
	return chunk
}

func TestReadEventsDecodesBatches(t *testing.T) {
	var pipe [2]int
	if err := syscall.Pipe(pipe[:]); err != nil {
		t.Fatalf("create pipe: %v", err)
	}
	defer syscall.Close(pipe[0])

	payload := append(encodeEvent(evKey, keyA, valueDown), encodeEvent(evKey, keyA, valueUp)...)
	payload = append(payload, encodeEvent(evKey, 36, valueRepeat)...)
	if _, err := syscall.Write(pipe[1], payload); err != nil {
		t.Fatalf("write events: %v", err)
	}
	_ = syscall.Close(pipe[1])

	events, err := readEvents(pipe[0], make([]byte, readBufSize))
	if err != nil {
		t.Fatalf("read events: %v", err)
	}
	if len(events) != 3 {
		t.Fatalf("got %d events, want 3", len(events))
	}

	if events[0].Type != evKey || events[0].Code != keyA || events[0].Value != valueDown {
		t.Fatalf("first event decoded as %+v", events[0])
	}
	if events[1].Value != valueUp {
		t.Fatalf("second event value %d, want %d", events[1].Value, valueUp)
	}
	if events[2].Code != 36 || events[2].Value != valueRepeat {
		t.Fatalf("third event decoded as %+v", events[2])
	}
	if events[0].Seconds != 1700000000 || events[0].Microseconds != 250000 {
		t.Fatalf("timestamp decoded as %d.%d", events[0].Seconds, events[0].Microseconds)
	}
}

func TestReadEventsIgnoresPartialTrailer(t *testing.T) {
	var pipe [2]int
	if err := syscall.Pipe(pipe[:]); err != nil {
		t.Fatalf("create pipe: %v", err)
	}
	defer syscall.Close(pipe[0])

	payload := append(encodeEvent(evKey, keyZ, valueDown), 0x01, 0x02, 0x03)
	if _, err := syscall.Write(pipe[1], payload); err != nil {
		t.Fatalf("write events: %v", err)
	}
	_ = syscall.Close(pipe[1])

	events, err := readEvents(pipe[0], make([]byte, readBufSize))
	if err != nil {
		t.Fatalf("read events: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("got %d events, want 1", len(events))
	}
}
