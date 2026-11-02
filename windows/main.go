package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	magic       = "KBR1"
	hkdfInfo    = "keybridge v1"
	readTimeout = 10 * time.Second

	msgHello      = 0x01
	msgKey        = 0x02
	msgReleaseAll = 0x03
	msgPing       = 0x04
	msgMove       = 0x05
	msgButton     = 0x06
	msgWheel      = 0x07
	msgPinch      = 0x08
)

func main() {
	port := flag.Int("port", 24830, "TCP port to listen on")
	reset := flag.Bool("reset", false, "generate a new pairing code")
	flag.Parse()

	secret, err := loadOrCreateSecret(*reset)
	if err != nil {
		log.Fatalf("pairing code: %v", err)
	}

	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("listen: %v", err)
	}

	fmt.Println("KeyBridge receiver is running.")
	fmt.Println()
	fmt.Println("  In the Mac menu bar app, choose \"Set Windows address & pairing code…\" and enter:")
	for _, ip := range localIPs() {
		fmt.Printf("    Address:       %s\n", ip)
	}
	fmt.Printf("    Port:          %d\n", *port)
	fmt.Printf("    Pairing code:  %s\n", secret)
	fmt.Println()
	fmt.Println("  Leave this window open. Close it (or Ctrl+C) to stop.")
	fmt.Println()

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept: %v", err)
			continue
		}
		go func() {
			defer conn.Close()
			if err := serve(conn, secret); err != nil && !errors.Is(err, io.EOF) {
				log.Printf("%s: %v", conn.RemoteAddr(), err)
			}
		}()
	}
}

var (
	currentMu sync.Mutex
	current   net.Conn
)

func serve(conn net.Conn, secret string) error {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return err
	}
	if _, err := conn.Write(append([]byte(magic), salt...)); err != nil {
		return err
	}

	key, err := hkdf.Key(sha256.New, []byte(normalizeSecret(secret)), salt, hkdfInfo, 32)
	if err != nil {
		return err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}

	var lastCounter uint64
	authed := false
	pressed := map[uint16]bool{}
	buttons := map[uint8]bool{}

	defer func() {
		if authed {
			releaseAll(pressed, buttons)
			currentMu.Lock()
			if current == conn {
				current = nil
			}
			currentMu.Unlock()
			log.Printf("%s disconnected", conn.RemoteAddr())
		}
	}()

	hdr := make([]byte, 10)
	for {
		conn.SetReadDeadline(time.Now().Add(readTimeout))
		if _, err := io.ReadFull(conn, hdr); err != nil {
			return err
		}
		n := binary.BigEndian.Uint16(hdr[0:2])
		counter := binary.BigEndian.Uint64(hdr[2:10])
		if n < uint16(gcm.Overhead()) || n > 256 {
			return fmt.Errorf("bad frame length %d", n)
		}
		body := make([]byte, n)
		if _, err := io.ReadFull(conn, body); err != nil {
			return err
		}
		if counter <= lastCounter {
			return errors.New("replayed or out-of-order frame")
		}
		nonce := make([]byte, 12)
		binary.BigEndian.PutUint64(nonce[4:], counter)
		msg, err := gcm.Open(nil, nonce, body, nil)
		if err != nil {
			return errors.New("wrong pairing code (decryption failed)")
		}
		lastCounter = counter
		if len(msg) == 0 {
			continue
		}

		if !authed {
			if msg[0] != msgHello {
				return errors.New("expected hello")
			}
			currentMu.Lock()
			if current != nil {
				current.Close()
			}
			current = conn
			currentMu.Unlock()
			authed = true
			log.Printf("%s connected — Mac keyboard and trackpad are linked", conn.RemoteAddr())
			continue
		}

		switch msg[0] {
		case msgKey:
			if len(msg) < 4 {
				continue
			}
			scan := binary.BigEndian.Uint16(msg[1:3])
			down := msg[3] == 1
			if !down && !pressed[scan] {
				continue
			}
			if down {
				pressed[scan] = true
			} else {
				delete(pressed, scan)
			}
			sendKey(scan, down)
		case msgMove:
			if len(msg) >= 5 {
				moveMouse(int32(int16(binary.BigEndian.Uint16(msg[1:3]))), int32(int16(binary.BigEndian.Uint16(msg[3:5]))))
			}
		case msgButton:
			if len(msg) < 3 {
				continue
			}
			b, down := msg[1], msg[2] == 1
			if !down && !buttons[b] {
				continue
			}
			if down {
				buttons[b] = true
			} else {
				delete(buttons, b)
			}
			mouseButton(b, down)
		case msgWheel:
			if len(msg) >= 5 {
				wheel(int16(binary.BigEndian.Uint16(msg[1:3])), int16(binary.BigEndian.Uint16(msg[3:5])))
			}
		case msgPinch:
			if len(msg) < 4 {
				continue
			}
			switch scale := float64(binary.BigEndian.Uint16(msg[2:4])) / 1000; msg[1] {
			case 0:
				pinchBegin()
			case 1:
				pinchUpdate(scale)
			default:
				pinchEnd()
			}
		case msgReleaseAll:
			releaseAll(pressed, buttons)
		case msgPing:
		}
	}
}

func releaseAll(pressed map[uint16]bool, buttons map[uint8]bool) {
	pinchEnd()
	for scan := range pressed {
		sendKey(scan, false)
		delete(pressed, scan)
	}
	for b := range buttons {
		mouseButton(b, false)
		delete(buttons, b)
	}
}

func loadOrCreateSecret(reset bool) (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	dir = filepath.Join(dir, "KeyBridge")
	path := filepath.Join(dir, "pairing-code.txt")

	if !reset {
		if b, err := os.ReadFile(path); err == nil {
			if s := strings.TrimSpace(string(b)); len(normalizeSecret(s)) >= 16 {
				return s, nil
			}
		}
	}

	raw := make([]byte, 13)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	code := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(raw)[:20]
	code = code[0:5] + "-" + code[5:10] + "-" + code[10:15] + "-" + code[15:20]

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	if err := os.WriteFile(path, []byte(code+"\n"), 0o600); err != nil {
		return "", err
	}
	return code, nil
}

func normalizeSecret(s string) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(s) {
		if r != '-' && r != ' ' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func localIPs() []string {
	var ips []string
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, a := range addrs {
			if ipn, ok := a.(*net.IPNet); ok && ipn.IP.To4() != nil && !ipn.IP.IsLinkLocalUnicast() {
				ips = append(ips, ipn.IP.String())
			}
		}
	}
	if len(ips) == 0 {
		ips = append(ips, "(no network found — check Wi-Fi)")
	}
	return ips
}
