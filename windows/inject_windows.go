package main

import (
	"log"
	"syscall"
	"unsafe"
)

var procSendInput = syscall.NewLazyDLL("user32.dll").NewProc("SendInput")

const (
	inputKeyboard        = 1
	keyeventfExtendedKey = 0x0001
	keyeventfKeyUp       = 0x0002
	keyeventfScanCode    = 0x0008
)

type keybdInput struct {
	wVk         uint16
	wScan       uint16
	dwFlags     uint32
	time        uint32
	dwExtraInfo uintptr
}

// Win32 INPUT: the union is sized by MOUSEINPUT, 8 bytes larger than KEYBDINPUT.
type input struct {
	inputType uint32
	ki        keybdInput
	_         [8]byte
}

func sendKey(scan uint16, down bool) {
	flags := uint32(keyeventfScanCode)
	if scan&0xFF00 == 0xE000 {
		flags |= keyeventfExtendedKey
	}
	if !down {
		flags |= keyeventfKeyUp
	}
	in := input{inputType: inputKeyboard, ki: keybdInput{wScan: scan & 0xFF, dwFlags: flags}}
	n, _, err := procSendInput.Call(1, uintptr(unsafe.Pointer(&in)), unsafe.Sizeof(in))
	if n != 1 {
		log.Printf("SendInput failed: %v", err)
	}
}
