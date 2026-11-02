package main

import (
	"encoding/binary"
	"log"
	"sync"
	"time"
	"unsafe"
)

var (
	procInitTouch   = user32.NewProc("InitializeTouchInjection")
	procInjectTouch = user32.NewProc("InjectTouchInput")
)

const (
	ptTouch            = 2
	touchFeedbackNone  = 3
	pointerFlagInRange = 0x0002
	pointerFlagContact = 0x0004
	pointerFlagDown    = 0x10000
	pointerFlagUpdate  = 0x20000
	pointerFlagUp      = 0x40000
	pinchSpan          = 200.0
)

// POINTER_TOUCH_INFO, written by offset because POINTER_INFO's padding differs between 386 and amd64.
var (
	ptrSize        = int(unsafe.Sizeof(uintptr(0)))
	pointerInfoLen = map[int]int{4: 88, 8: 96}[ptrSize]
	touchInfoLen   = pointerInfoLen + 48
)

var pinchState struct {
	sync.Mutex
	initOnce sync.Once
	ready    bool
	active   bool
	cx, cy   int32
	scale    float64
	stop     chan struct{}
}

func touchReady() bool {
	pinchState.initOnce.Do(func() {
		if procInitTouch.Find() != nil {
			log.Printf("touch injection needs Windows 8 or later")
			return
		}
		r, _, err := procInitTouch.Call(2, touchFeedbackNone)
		if r == 0 {
			log.Printf("InitializeTouchInjection failed: %v", err)
		}
		pinchState.ready = r != 0
	})
	return pinchState.ready
}

func writeContact(b []byte, id uint32, flags uint32, x, y int32) {
	le := binary.LittleEndian
	le.PutUint32(b[0:], ptTouch)
	le.PutUint32(b[4:], id)
	le.PutUint32(b[12:], flags)
	pt := 16 + 2*ptrSize
	le.PutUint32(b[pt:], uint32(x))
	le.PutUint32(b[pt+4:], uint32(y))
	t := pointerInfoLen
	le.PutUint32(b[t+4:], 0x7)
	for i, v := range []int32{x - 2, y - 2, x + 2, y + 2} {
		le.PutUint32(b[t+8+4*i:], uint32(v))
	}
	le.PutUint32(b[t+40:], 90)
	le.PutUint32(b[t+44:], 32000)
}

func injectPinch(flags uint32) {
	s := &pinchState
	vx, vw := metric(smXVirtualScreen), metric(smCXVirtualScreen)
	half := int32(max(pinchSpan*s.scale/2, 10))
	buf := make([]byte, 2*touchInfoLen)
	for i, x := range []int32{s.cx - half, s.cx + half} {
		x = min(max(x, vx), vx+vw-1)
		writeContact(buf[i*touchInfoLen:], uint32(i), flags, x, s.cy)
	}
	if r, _, err := procInjectTouch.Call(2, uintptr(unsafe.Pointer(&buf[0]))); r == 0 {
		log.Printf("InjectTouchInput failed: %v", err)
	}
}

func pinchBegin() {
	s := &pinchState
	s.Lock()
	defer s.Unlock()
	if !touchReady() {
		return
	}
	if s.active {
		injectPinch(pointerFlagUp)
		close(s.stop)
	}
	var pt struct{ x, y int32 }
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	s.cx, s.cy, s.scale, s.active = pt.x, pt.y, 1, true
	injectPinch(pointerFlagDown | pointerFlagInRange | pointerFlagContact)

	// Windows cancels touch contacts that stop receiving updates, so keep them alive while fingers rest.
	s.stop = make(chan struct{})
	go func(stop chan struct{}) {
		t := time.NewTicker(100 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-stop:
				return
			case <-t.C:
				s.Lock()
				if s.active {
					injectPinch(pointerFlagUpdate | pointerFlagInRange | pointerFlagContact)
				}
				s.Unlock()
			}
		}
	}(s.stop)
}

func pinchUpdate(scale float64) {
	s := &pinchState
	s.Lock()
	defer s.Unlock()
	if s.active {
		s.scale = scale
		injectPinch(pointerFlagUpdate | pointerFlagInRange | pointerFlagContact)
	}
}

func pinchEnd() {
	s := &pinchState
	s.Lock()
	defer s.Unlock()
	if s.active {
		injectPinch(pointerFlagUp)
		s.active = false
		close(s.stop)
	}
}
