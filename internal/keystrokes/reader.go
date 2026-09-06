package keystrokes

import (
	"encoding/binary"
	"errors"
	"fmt"
	"syscall"
	"time"
)

const (
	evKey = 1

	valueUp     = 0
	valueDown   = 1
	valueRepeat = 2

	eventSize   = 24
	readBufSize = eventSize * 64

	selectTimeout = 200 * time.Millisecond

	// duplicateWindow suppresses the same press arriving twice when one
	// physical keyboard publishes more than one evdev node.
	duplicateWindow = 5 * time.Millisecond
)

type rawEvent struct {
	Seconds      int64
	Microseconds int64
	Type         uint16
	Code         uint16
	Value        int32
}

type keyEvent struct {
	device int
	code   uint16
	value  int32
	at     time.Time
}

type deviceSet struct {
	descriptors []int
	names       []string
}

func openDevices(devices []Device) (*deviceSet, error) {
	set := &deviceSet{}
	for _, device := range devices {
		descriptor, err := syscall.Open(device.Path, syscall.O_RDONLY|syscall.O_NONBLOCK, 0)
		if err != nil {
			continue
		}
		set.descriptors = append(set.descriptors, descriptor)
		set.names = append(set.names, device.Name)
	}
	if len(set.descriptors) == 0 {
		return nil, errors.New("no readable keyboard devices; add your user to the \"input\" group")
	}
	return set, nil
}

func (set *deviceSet) close() {
	for _, descriptor := range set.descriptors {
		_ = syscall.Close(descriptor)
	}
	set.descriptors = nil
	set.names = nil
}

func (set *deviceSet) selectReady() ([]int, error) {
	var (
		fdSet   syscall.FdSet
		highest int
	)
	for _, descriptor := range set.descriptors {
		fdSet.Bits[descriptor/64] |= int64(1) << uint(descriptor%64)
		if descriptor > highest {
			highest = descriptor
		}
	}
	timeout := syscall.Timeval{Usec: int64(selectTimeout / time.Microsecond)}
	count, err := syscall.Select(highest+1, &fdSet, nil, nil, &timeout)
	if err != nil {
		if errors.Is(err, syscall.EINTR) {
			return nil, nil
		}
		return nil, fmt.Errorf("wait for key events: %w", err)
	}
	if count <= 0 {
		return nil, nil
	}

	var ready []int
	for index, descriptor := range set.descriptors {
		if fdSet.Bits[descriptor/64]&(int64(1)<<uint(descriptor%64)) != 0 {
			ready = append(ready, index)
		}
	}
	return ready, nil
}

func readEvents(descriptor int, buffer []byte) ([]rawEvent, error) {
	read, err := syscall.Read(descriptor, buffer)
	if err != nil {
		if errors.Is(err, syscall.EAGAIN) || errors.Is(err, syscall.EINTR) {
			return nil, nil
		}
		return nil, err
	}
	if read <= 0 {
		return nil, nil
	}

	events := make([]rawEvent, 0, read/eventSize)
	for offset := 0; offset+eventSize <= read; offset += eventSize {
		chunk := buffer[offset : offset+eventSize]
		events = append(events, rawEvent{
			Seconds:      int64(binary.LittleEndian.Uint64(chunk[0:8])),
			Microseconds: int64(binary.LittleEndian.Uint64(chunk[8:16])),
			Type:         binary.LittleEndian.Uint16(chunk[16:18]),
			Code:         binary.LittleEndian.Uint16(chunk[18:20]),
			Value:        int32(binary.LittleEndian.Uint32(chunk[20:24])),
		})
	}
	return events, nil
}
