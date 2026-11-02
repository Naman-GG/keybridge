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
