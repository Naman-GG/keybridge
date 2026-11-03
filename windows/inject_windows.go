package main

import (
	"log"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var (
	user32               = syscall.NewLazyDLL("user32.dll")
	procSendInput        = user32.NewProc("SendInput")
	procGetCursorPos     = user32.NewProc("GetCursorPos")
	procGetSystemMetrics = user32.NewProc("GetSystemMetrics")
	procSetDPIAware      = user32.NewProc("SetProcessDPIAware")
)

const (
	inputMouse           = 0
	inputKeyboard        = 1
	keyeventfExtendedKey = 0x0001
	keyeventfKeyUp       = 0x0002
	keyeventfScanCode    = 0x0008
	mouseeventfMove      = 0x0001
	mouseeventfWheel     = 0x0800
	mouseeventfHWheel    = 0x1000
	mouseeventfVirtDesk  = 0x4000
	mouseeventfAbsolute  = 0x8000
	smXVirtualScreen     = 76
	smYVirtualScreen     = 77
	smCXVirtualScreen    = 78
	smCYVirtualScreen    = 79
)

type keybdInput struct {
	wVk         uint16
	wScan       uint16
	dwFlags     uint32
	time        uint32
	dwExtraInfo uintptr
}

type mouseInput struct {
	dx          int32
	dy          int32
	mouseData   uint32
	dwFlags     uint32
	time        uint32
	dwExtraInfo uintptr
}

// Win32 INPUT: the union is sized by MOUSEINPUT, 8 bytes larger than KEYBDINPUT.
type keyboardEvent struct {
	inputType uint32
	ki        keybdInput
	_         [8]byte
}

type mouseEvent struct {
	inputType uint32
	mi        mouseInput
}

func init() {
	procSetDPIAware.Call()
}

func sendInput(p unsafe.Pointer, size uintptr) {
	if n, _, err := procSendInput.Call(1, uintptr(p), size); n != 1 {
		log.Printf("SendInput failed: %v", err)
	}
}

func sendKey(scan uint16, down bool) {
	flags := uint32(keyeventfScanCode)
	if scan&0xFF00 == 0xE000 {
		flags |= keyeventfExtendedKey
	}
	if !down {
		flags |= keyeventfKeyUp
	}
	in := keyboardEvent{inputType: inputKeyboard, ki: keybdInput{wScan: scan & 0xFF, dwFlags: flags}}
	sendInput(unsafe.Pointer(&in), unsafe.Sizeof(in))
}

func sendMouse(mi mouseInput) {
	in := mouseEvent{inputType: inputMouse, mi: mi}
	sendInput(unsafe.Pointer(&in), unsafe.Sizeof(in))
}

func metric(i uintptr) int32 {
	v, _, _ := procGetSystemMetrics.Call(i)
	return int32(v)
}

// Moves to an absolute position so Windows' pointer acceleration isn't applied on top of the Mac's.
// GetCursorPos lags behind injected moves, so moves arriving in a burst would each start from a stale
// position and lose distance. Moves that follow closely start from where the previous one was sent.
var lastMove struct {
	sync.Mutex
	x, y int32
	at   time.Time
}

func moveMouse(dx, dy int32) {
	lastMove.Lock()
	defer lastMove.Unlock()
	var pt struct{ x, y int32 }
	if time.Since(lastMove.at) < 100*time.Millisecond {
		pt.x, pt.y = lastMove.x, lastMove.y
	} else {
		procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	}
	vx, vy := metric(smXVirtualScreen), metric(smYVirtualScreen)
	vw, vh := metric(smCXVirtualScreen), metric(smCYVirtualScreen)
	if vw <= 0 || vh <= 0 {
		return
	}
	x := min(max(pt.x+dx, vx), vx+vw-1) - vx
	y := min(max(pt.y+dy, vy), vy+vh-1) - vy
	lastMove.x, lastMove.y, lastMove.at = x+vx, y+vy, time.Now()
	sendMouse(mouseInput{
		dx:      int32((int64(x)*65536 + 32768) / int64(vw)),
		dy:      int32((int64(y)*65536 + 32768) / int64(vh)),
		dwFlags: mouseeventfMove | mouseeventfAbsolute | mouseeventfVirtDesk,
	})
}

var buttonFlags = [3][2]uint32{{0x0004, 0x0002}, {0x0010, 0x0008}, {0x0040, 0x0020}}

func mouseButton(b uint8, down bool) {
	if int(b) >= len(buttonFlags) {
		return
	}
	i := 0
	if down {
		i = 1
	}
	sendMouse(mouseInput{dwFlags: buttonFlags[b][i]})
}

func wheel(v, h int16) {
	if v != 0 {
		sendMouse(mouseInput{mouseData: uint32(int32(v)), dwFlags: mouseeventfWheel})
	}
	if h != 0 {
		sendMouse(mouseInput{mouseData: uint32(int32(h)), dwFlags: mouseeventfHWheel})
	}
}
