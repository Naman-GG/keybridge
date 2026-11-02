//go:build !windows

package main

import "log"

func sendKey(scan uint16, down bool) {
	state := "up"
	if down {
		state = "down"
	}
	log.Printf("key %#04x %s", scan, state)
}

func moveMouse(dx, dy int32) { log.Printf("move %d,%d", dx, dy) }

func mouseButton(b uint8, down bool) { log.Printf("button %d down=%v", b, down) }

func wheel(v, h int16) { log.Printf("wheel %d,%d", v, h) }
