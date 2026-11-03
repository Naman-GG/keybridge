
import AppKit
import CryptoKit
import Network

let scanCodes: [UInt16: UInt16] = [
    0x00: 0x1E, 0x01: 0x1F, 0x02: 0x20, 0x03: 0x21, 0x04: 0x23, 0x05: 0x22,
    0x06: 0x2C, 0x07: 0x2D, 0x08: 0x2E, 0x09: 0x2F, 0x0A: 0x56, 0x0B: 0x30,
    0x0C: 0x10, 0x0D: 0x11, 0x0E: 0x12, 0x0F: 0x13, 0x10: 0x15, 0x11: 0x14,
    0x12: 0x02, 0x13: 0x03, 0x14: 0x04, 0x15: 0x05, 0x16: 0x07, 0x17: 0x06,
    0x18: 0x0D, 0x19: 0x0A, 0x1A: 0x08, 0x1B: 0x0C, 0x1C: 0x09, 0x1D: 0x0B,
    0x1E: 0x1B, 0x1F: 0x18, 0x20: 0x16, 0x21: 0x1A, 0x22: 0x17, 0x23: 0x19,
    0x24: 0x1C, 0x25: 0x26, 0x26: 0x24, 0x27: 0x28, 0x28: 0x25, 0x29: 0x27,
    0x2A: 0x2B, 0x2B: 0x33, 0x2C: 0x35, 0x2D: 0x31, 0x2E: 0x32, 0x2F: 0x34,
    0x30: 0x0F, 0x31: 0x39, 0x32: 0x29, 0x33: 0x0E, 0x35: 0x01,
    0x39: 0x3A,
    0x7A: 0x3B, 0x78: 0x3C, 0x63: 0x3D, 0x76: 0x3E, 0x60: 0x3F, 0x61: 0x40,
    0x62: 0x41, 0x64: 0x42, 0x65: 0x43, 0x6D: 0x44, 0x67: 0x57, 0x6F: 0x58,
    0x69: 0x64, 0x6B: 0x65, 0x71: 0x66, 0x6A: 0x67, 0x40: 0x68, 0x4F: 0x69, 0x50: 0x6A,
    0x7B: 0xE04B, 0x7C: 0xE04D, 0x7D: 0xE050, 0x7E: 0xE048,
    0x73: 0xE047, 0x77: 0xE04F, 0x74: 0xE049, 0x79: 0xE051,
    0x75: 0xE053, 0x72: 0xE052,
    0x52: 0x52, 0x53: 0x4F, 0x54: 0x50, 0x55: 0x51, 0x56: 0x4B, 0x57: 0x4C,
    0x58: 0x4D, 0x59: 0x47, 0x5B: 0x48, 0x5C: 0x49, 0x41: 0x53, 0x43: 0x37,
    0x45: 0x4E, 0x4E: 0x4A, 0x4B: 0xE035, 0x4C: 0xE01C, 0x51: 0x59, 0x47: 0x45,
    0x5D: 0x7D, 0x5E: 0x73, 0x5F: 0x7E,
]

enum PCMod { case ctrl, alt, win }

let leftScan: [PCMod: UInt16] = [.ctrl: 0x1D, .alt: 0x38, .win: 0xE05B]
let rightScan: [PCMod: UInt16] = [.ctrl: 0xE01D, .alt: 0xE038, .win: 0xE05C]

enum Layout: String, CaseIterable {
    case macStyle, positional

    var title: String {
        switch self {
        case .macStyle: return "Mac-style  (⌘→Ctrl, ⌥→Alt, ⌃→Win)"
        case .positional: return "PC positions  (⌘→Alt, ⌥→Win, ⌃→Ctrl)"
        }
    }

    func map(_ mac: String) -> PCMod {
        switch (self, mac) {
        case (.macStyle, "cmd"): return .ctrl
        case (.macStyle, "opt"): return .alt
        case (.macStyle, _): return .win
        case (.positional, "cmd"): return .alt
        case (.positional, "opt"): return .win
        case (.positional, _): return .ctrl
        }
    }
}

struct ModKey { let name: String; let right: Bool; let mask: UInt64 }
let modifierKeys: [UInt16: ModKey] = [
    0x37: ModKey(name: "cmd", right: false, mask: 0x08),
    0x36: ModKey(name: "cmd", right: true, mask: 0x10),
    0x3A: ModKey(name: "opt", right: false, mask: 0x20),
    0x3D: ModKey(name: "opt", right: true, mask: 0x40),
    0x3B: ModKey(name: "ctrl", right: false, mask: 0x01),
    0x3E: ModKey(name: "ctrl", right: true, mask: 0x2000),
    0x38: ModKey(name: "shift", right: false, mask: 0x02),
    0x3C: ModKey(name: "shift", right: true, mask: 0x04),
]
let rightCommand: UInt16 = 0x36

let moveTypes: Set<CGEventType> = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
let buttonTypes: [CGEventType: (button: UInt8, down: Bool)] = [
    .leftMouseDown: (0, true), .leftMouseUp: (0, false),
    .rightMouseDown: (1, true), .rightMouseUp: (1, false),
    .otherMouseDown: (2, true), .otherMouseUp: (2, false),
]
let pointerSpeeds: [Double] = [1, 1.5, 2, 3]
let scrollScale = 3.0
let gestureEvent: UInt32 = 29
let dockGestureEvent: UInt32 = 30
let capsLock: UInt16 = 0x39

final class Link {
    enum State { case idle, connecting, connected, failed(String) }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle { didSet { onStateChange?(state) } }

    private var conn: NWConnection?
    private var key: SymmetricKey?
    private var counter: UInt64 = 0
    private var host = "", port: UInt16 = 24830, secret = ""
    private var retry: Timer?, ping: Timer?

    var isConnected: Bool { if case .connected = state { return true } else { return false } }

    func connect(host: String, port: UInt16, secret: String) {
        self.host = host; self.port = port; self.secret = secret
        reconnect()
    }

    private func reconnect() {
        teardown()
        guard !host.isEmpty, let p = NWEndpoint.Port(rawValue: port) else { state = .idle; return }
        state = .connecting
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 5
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: NWParameters(tls: nil, tcp: tcp))
        conn = c
        c.stateUpdateHandler = { [weak self, weak c] st in
            guard let self, let c, c === self.conn else { return }
            switch st {
            case .ready: self.readHandshake(c)
            case .failed(let e), .waiting(let e): self.fail(e.localizedDescription)
            default: break
            }
        }
        c.start(queue: .main)
    }

    private func readHandshake(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 20, maximumLength: 20) { [weak self] data, _, _, err in
            guard let self, c === self.conn else { return }
            guard let data, data.count == 20, data.prefix(4) == Data("KBR1".utf8) else {
                self.fail(err?.localizedDescription ?? "not a KeyBridge receiver"); return
            }
            self.key = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: Data(Link.normalize(self.secret).utf8)),
                salt: data.suffix(16), info: Data("keybridge v1".utf8), outputByteCount: 32)
            self.counter = 0
            self.send([0x01])
            self.state = .connected
            self.ping = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.send([0x04]) }
            self.watchForClose(c)
        }
    }

    private func watchForClose(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, _, _ in
            guard let self, c === self.conn else { return }
            self.fail("Windows closed the connection — check the pairing code")
        }
    }

    func sendKey(scan: UInt16, down: Bool) {
        send([0x02, UInt8(scan >> 8), UInt8(scan & 0xFF), down ? 1 : 0])
    }

    func sendReleaseAll() { send([0x03]) }

    func sendMove(dx: Int16, dy: Int16) { send([0x05] + Link.be(dx) + Link.be(dy)) }

    func sendButton(_ b: UInt8, down: Bool) { send([0x06, b, down ? 1 : 0]) }

    func sendWheel(v: Int16, h: Int16) { send([0x07] + Link.be(v) + Link.be(h)) }

    func sendPinch(_ phase: UInt8, scale: Double) {
        send([0x08, phase] + Link.be(Int16(bitPattern: UInt16(min(max(scale, 0.05), 60) * 1000))))
    }

    static func be(_ v: Int16) -> [UInt8] { [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }

    // Frame: u16 length | u64 counter | AES-GCM(msg); nonce = 0000 ‖ counter
    private func send(_ msg: [UInt8]) {
        guard let conn, let key else { return }
        counter += 1
        var nonceBytes = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { nonceBytes.append(contentsOf: $0) }
        guard let box = try? AES.GCM.seal(Data(msg), using: key, nonce: AES.GCM.Nonce(data: nonceBytes)) else { return }
        let body = box.ciphertext + box.tag
        var frame = Data()
        withUnsafeBytes(of: UInt16(body.count).bigEndian) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: counter.bigEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        conn.send(content: frame, completion: .contentProcessed { [weak self] err in
            if let err, conn === self?.conn { self?.fail(err.localizedDescription) }
        })
    }

    private func fail(_ why: String) {
        teardown()
        state = .failed(why)
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.reconnect() }
    }

    private func teardown() {
        retry?.invalidate(); ping?.invalidate()
        conn?.cancel(); conn = nil; key = nil
    }

    static func normalize(_ s: String) -> String {
        s.uppercased().filter { $0 != "-" && $0 != " " }
    }
}

enum Swipe { case up, down, left, right }

final class SwipeRecognizer {
    var onSwipe: ((Int, Swipe) -> Void)?
    private var start: [Int32: CGPoint] = [:]
    private var fingers = 0
    private var fired = false

    func frame(_ touches: [(id: Int32, pos: CGPoint)]) {
        if touches.isEmpty { start = [:]; fingers = 0; fired = false; return }
        if fired { return }
        if touches.count < 3 { start = [:]; fingers = 0; return }
        if touches.count != fingers {
            fingers = touches.count
            start = Dictionary(touches.map { ($0.id, $0.pos) }, uniquingKeysWith: { a, _ in a })
            return
        }
        var dx = 0.0, dy = 0.0
        for t in touches {
            guard let p = start[t.id] else { return }
            dx += (t.pos.x - p.x) / Double(touches.count)
            dy += (t.pos.y - p.y) / Double(touches.count)
        }
        guard max(abs(dx), abs(dy)) > 0.12 else { return }
        fired = true
        let dir: Swipe = abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy > 0 ? .up : .down)
        let n = min(fingers, 4)
        DispatchQueue.main.async { self.onSwipe?(n, dir) }
    }
}

let swipes = SwipeRecognizer()

// Raw finger positions from the private MultitouchSupport framework; each touch record is 96 bytes.
// Devices are started once and never stopped: stopping right after starting crashes inside the framework.
final class Multitouch {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private var deviceList: CFArray?

    init() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let list = dlsym(h, "MTDeviceCreateList"), let register = dlsym(h, "MTRegisterContactFrameCallback"),
              let start = dlsym(h, "MTDeviceStart") else { return }
        typealias ListFn = @convention(c) () -> Unmanaged<CFArray>
        typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
        typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        let array = unsafeBitCast(list, to: ListFn.self)().takeRetainedValue()
        deviceList = array
        let callback: Callback = { _, data, count, _, _ in
            var touches: [(id: Int32, pos: CGPoint)] = []
            if let data {
                for i in 0..<Int(count) {
                    let f = data + i * 96
                    let state = f.load(fromByteOffset: 20, as: Int32.self)
                    guard state == 4 || state == 5 else { continue }
                    touches.append((f.load(fromByteOffset: 16, as: Int32.self),
                                    CGPoint(x: Double(f.load(fromByteOffset: 32, as: Float.self)),
                                            y: Double(f.load(fromByteOffset: 36, as: Float.self)))))
                }
            }
            swipes.frame(touches)
            return 0
        }
        for i in 0..<CFArrayGetCount(array) {
            guard let d = CFArrayGetValueAtIndex(array, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: d)
            unsafeBitCast(register, to: RegisterFn.self)(device, callback)
            unsafeBitCast(start, to: StartFn.self)(device, 0)
        }
    }
}

final class App: NSObject, NSApplicationDelegate {
    let link = Link()
    var statusItem: NSStatusItem!
    var tap: CFMachPort?
    var mouseTap: CFMachPort?
    var tapRetry: Timer?
    var parkPoint = CGPoint.zero
    var moveRest = CGPoint.zero
    var scrollRest = CGPoint.zero
    let multitouch = Multitouch()
    var pinchRest = 0.0
    var pinchCtrl = false
    var pinchTimer: Timer?
    var pinchScale: Double?

    var remote = false
    var screenLocked = false
    var sentDown = Set<UInt16>()
    var pendingRightCmd = false
    var lastRightCmdTap: TimeInterval = 0
    var keySinceRightCmd = true

    let defaults = UserDefaults.standard
    var layout: Layout {
        get { Layout(rawValue: defaults.string(forKey: "layout") ?? "") ?? .macStyle }
        set { defaults.set(newValue.rawValue, forKey: "layout"); rebuildMenu() }
    }
    var pageZoomPinch: Bool {
        get { defaults.bool(forKey: "pageZoomPinch") }
        set { endPinch(); defaults.set(newValue, forKey: "pageZoomPinch"); rebuildMenu() }
    }
    var pointerSpeed: Double {
        get { defaults.object(forKey: "pointerSpeed") as? Double ?? 1.5 }
        set { defaults.set(newValue, forKey: "pointerSpeed"); rebuildMenu() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .systemFont(ofSize: 13, weight: .medium)
        link.onStateChange = { [weak self] _ in
            guard let self else { return }
            if self.remote && !self.link.isConnected { self.setRemote(false) }
            self.rebuildMenu()
        }
        rebuildMenu()
        installTap()
        swipes.onSwipe = { [weak self] n, dir in self?.swipe(fingers: n, dir) }
        watchForLockAndSleep()

        if let host = defaults.string(forKey: "host"), let secret = defaults.string(forKey: "secret") {
            link.connect(host: host, port: UInt16(defaults.integer(forKey: "port")).nonZero ?? 24830, secret: secret)
        } else {
            DispatchQueue.main.async { self.askForAddress() }
        }
    }

    func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let app = Unmanaged<App>.fromOpaque(refcon!).takeUnretainedValue()
            return app.handle(type: type, event: event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            if tapRetry == nil {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                tapRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.installTap() }
            }
            rebuildMenu()
            return
        }
        tapRetry?.invalidate(); tapRetry = nil
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let mouseMask = (moveTypes.union(buttonTypes.keys) + [.scrollWheel]).reduce(0) { $0 | (1 << $1.rawValue) } | (1 << gestureEvent) | (1 << dockGestureEvent)
        mouseTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                     eventsOfInterest: CGEventMask(mouseMask), callback: callback,
                                     userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let mouseTap {
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, mouseTap, 0), .commonModes)
            CGEvent.tapEnable(tap: mouseTap, enable: remote)
        }
        rebuildMenu()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: remote) }
            return Unmanaged.passUnretained(event)
        }
        if type == .scrollWheel || moveTypes.contains(type) || buttonTypes[type] != nil || [gestureEvent, dockGestureEvent].contains(type.rawValue) {
            return handleMouse(type: type, event: event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged {
            handleModifier(code: code, flags: event.flags.rawValue)
            return Unmanaged.passUnretained(event)
        }

        keySinceRightCmd = true
        guard remote else { return Unmanaged.passUnretained(event) }

        if let scan = scanCodes[code] {
            let down = type == .keyDown
            if down { flushPendingRightCmd() }
            send(scan, down: down)
        }
        return nil
    }

    func handleModifier(code: UInt16, flags: UInt64) {
        if code == capsLock {
            if remote { send(0x3A, down: true); send(0x3A, down: false) }
            return
        }
        guard let mod = modifierKeys[code] else { return }
        let down = flags & mod.mask != 0

        if code == rightCommand {
            if down {
                let now = ProcessInfo.processInfo.systemUptime
                if !keySinceRightCmd && now - lastRightCmdTap < 0.4 {
                    lastRightCmdTap = 0
                    pendingRightCmd = false
                    toggle()
                    return
                }
                lastRightCmdTap = now
                keySinceRightCmd = false
                if remote { pendingRightCmd = true }
            } else {
                if pendingRightCmd { pendingRightCmd = false; return }
                if remote { send(pcScan(mod), down: false) }
            }
            return
        }

        keySinceRightCmd = true
        guard remote else { return }
        if down { flushPendingRightCmd() }
        send(pcScan(mod), down: down)
    }

    func handleMouse(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard remote else { return Unmanaged.passUnretained(event) }

        if type.rawValue == gestureEvent {
            if let e = NSEvent(cgEvent: event), e.type == .magnify {
                pinch(e.magnification, ended: !e.phase.isDisjoint(with: [.ended, .cancelled]))
            }
            return nil
        }
        if type.rawValue == dockGestureEvent { return nil }

        if moveTypes.contains(type) {
            moveRest.x += event.getDoubleValueField(.mouseEventDeltaX) * pointerSpeed
            moveRest.y += event.getDoubleValueField(.mouseEventDeltaY) * pointerSpeed
            let dx = moveRest.x.rounded(.towardZero), dy = moveRest.y.rounded(.towardZero)
            moveRest.x -= dx; moveRest.y -= dy
            if dx != 0 || dy != 0 { link.sendMove(dx: Int16(clamping: Int(dx)), dy: Int16(clamping: Int(dy))) }
            if abs(event.location.x - parkPoint.x) > 1 || abs(event.location.y - parkPoint.y) > 1 {
                CGWarpMouseCursorPosition(parkPoint)
            }
        } else if let (button, down) = buttonTypes[type] {
            if type != .otherMouseDown && type != .otherMouseUp || event.getIntegerValueField(.mouseEventButtonNumber) == 2 {
                link.sendButton(button, down: down)
            }
        } else {
            scrollRest.y += event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) * scrollScale
            scrollRest.x -= event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) * scrollScale
            let v = scrollRest.y.rounded(.towardZero), h = scrollRest.x.rounded(.towardZero)
            scrollRest.y -= v; scrollRest.x -= h
            if v != 0 || h != 0 { link.sendWheel(v: Int16(clamping: Int(v)), h: Int16(clamping: Int(h))) }
        }
        return nil
    }

    func pinch(_ amount: Double, ended: Bool) {
        pinchTimer?.invalidate()
        if ended { endPinch(); return }
        if pageZoomPinch {
            if !sentDown.contains(0x1D) { send(0x1D, down: true); pinchCtrl = true }
            pinchRest += amount * 1200
            let v = pinchRest.rounded(.towardZero)
            pinchRest -= v
            if v != 0 { link.sendWheel(v: Int16(clamping: Int(v)), h: 0) }
        } else {
            if pinchScale == nil { pinchScale = 1; link.sendPinch(0, scale: 1) }
            pinchScale = min(max(pinchScale! * (1 + amount), 0.05), 60)
            link.sendPinch(1, scale: pinchScale!)
        }
        pinchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.endPinch() }
    }

    func endPinch() {
        pinchTimer?.invalidate()
        if pinchCtrl { send(0x1D, down: false); pinchCtrl = false }
        if let scale = pinchScale { link.sendPinch(2, scale: scale); pinchScale = nil }
        pinchRest = 0
    }

    func swipe(fingers: Int, _ dir: Swipe) {
        guard remote else { return }
        let threeFingerDrag = UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")?.bool(forKey: "TrackpadThreeFingerDrag") ?? false
        if fingers == 3 && threeFingerDrag { return }
        let win: UInt16 = 0xE05B, ctrl: UInt16 = 0x1D, alt: UInt16 = 0x38, shift: UInt16 = 0x2A
        switch (fingers, dir) {
        case (_, .up): press([win, 0x0F])
        case (_, .down): press([win, 0x20])
        case (3, .left): press([alt, 0x0F])
        case (3, .right): press([alt, shift, 0x0F])
        case (_, .left): press([ctrl, win, 0xE04D])
        case (_, .right): press([ctrl, win, 0xE04B])
        }
    }

    func press(_ combo: [UInt16]) {
        for s in combo { link.sendKey(scan: s, down: true) }
        for s in combo.reversed() where !sentDown.contains(s) { link.sendKey(scan: s, down: false) }
    }

    func pcScan(_ mod: ModKey) -> UInt16 {
        if mod.name == "shift" { return mod.right ? 0x36 : 0x2A }
        let pc = layout.map(mod.name)
        return (mod.right ? rightScan : leftScan)[pc]!
    }

    func flushPendingRightCmd() {
        guard pendingRightCmd else { return }
        pendingRightCmd = false
        send(pcScan(modifierKeys[rightCommand]!), down: true)
    }

    func send(_ scan: UInt16, down: Bool) {
        if down { sentDown.insert(scan) } else {
            guard sentDown.remove(scan) != nil else { return }
        }
        link.sendKey(scan: scan, down: down)
    }

    // While locked or asleep the Mac must get every click and key, or unlocking stalls waiting for input.
    func watchForLockAndSleep() {
        let backToMac: (Notification) -> Void = { [weak self] _ in
            guard let self, self.remote else { return }
            self.setRemote(false)
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] n in
            self?.screenLocked = true
            backToMac(n)
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main, using: backToMac)
        }
    }

    @objc func toggle() {
        if !remote && (!link.isConnected || screenLocked) {
            NSSound.beep()
            return
        }
        setRemote(!remote)
    }

    func setRemote(_ on: Bool) {
        if !on {
            endPinch()
            for scan in sentDown { link.sendKey(scan: scan, down: false) }
            sentDown.removeAll()
            link.sendReleaseAll()
        }
        pendingRightCmd = false
        remote = on
        if on {
            parkPoint = CGEvent(source: nil)?.location ?? .zero
            moveRest = .zero; scrollRest = .zero
            CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        }
        CGAssociateMouseAndMouseCursorPosition(on ? 0 : 1)
        if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: on) }
        NSSound(named: on ? "Tink" : "Pop")?.play()
        rebuildMenu()
    }

    func rebuildMenu() {
        let button = statusItem.button
        button?.title = remote ? "⌨︎ → Windows" : "⌨︎ Mac"
        button?.contentTintColor = remote ? .systemOrange : nil

        let menu = NSMenu()
        let status: String
        switch link.state {
        case .idle: status = "Not set up"
        case .connecting: status = "Connecting to \(defaults.string(forKey: "host") ?? "")…"
        case .connected: status = "Connected to \(defaults.string(forKey: "host") ?? "")"
        case .failed(let why): status = "Not connected: \(why)"
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        if tap == nil {
            menu.addItem(withTitle: "⚠️ Grant Accessibility access in System Settings", action: #selector(openAccessibility), keyEquivalent: "")
        }
        menu.addItem(.separator())

        let t = menu.addItem(withTitle: remote ? "Switch back to Mac" : "Switch to Windows", action: #selector(toggle), keyEquivalent: "")
        t.isEnabled = remote || link.isConnected
        let hint = menu.addItem(withTitle: "Shortcut: double-tap Right ⌘", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(.separator())

        let layoutItem = menu.addItem(withTitle: "Modifier keys on Windows", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for l in Layout.allCases {
            let item = sub.addItem(withTitle: l.title, action: #selector(pickLayout(_:)), keyEquivalent: "")
            item.representedObject = l.rawValue
            item.state = l == layout ? .on : .off
        }
        layoutItem.submenu = sub

        let speedItem = menu.addItem(withTitle: "Pointer speed on Windows", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu()
        for v in pointerSpeeds {
            let item = speedMenu.addItem(withTitle: v.formatted() + "×", action: #selector(pickSpeed(_:)), keyEquivalent: "")
            item.representedObject = v
            item.state = v == pointerSpeed ? .on : .off
            item.target = self
        }
        speedItem.submenu = speedMenu

        let pinchItem = menu.addItem(withTitle: "Pinch on Windows", action: nil, keyEquivalent: "")
        let pinchMenu = NSMenu()
        for (title, page) in [("Zoom in where you pinch (like Chrome)", false), ("Change page zoom (Ctrl + scroll)", true)] {
            let item = pinchMenu.addItem(withTitle: title, action: #selector(pickPinch(_:)), keyEquivalent: "")
            item.representedObject = page
            item.state = page == pageZoomPinch ? .on : .off
            item.target = self
        }
        pinchItem.submenu = pinchMenu

        menu.addItem(withTitle: "Set Windows address & pairing code…", action: #selector(askForAddress), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit KeyBridge", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        for item in sub.items { item.target = self }
        statusItem.menu = menu
    }

    @objc func pickPinch(_ sender: NSMenuItem) {
        if let page = sender.representedObject as? Bool { pageZoomPinch = page }
    }

    @objc func pickSpeed(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double { pointerSpeed = v }
    }

    @objc func pickLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let l = Layout(rawValue: raw) else { return }
        if remote { setRemote(false) }
        layout = l
    }

    @objc func askForAddress() {
        let alert = NSAlert()
        alert.messageText = "Connect to your Windows laptop"
        alert.informativeText = "Run KeyBridge.exe on Windows. It shows the address and pairing code to enter here."
        let host = NSTextField(frame: NSRect(x: 0, y: 58, width: 280, height: 24))
        host.placeholderString = "Address, e.g. 192.168.1.42"
        host.stringValue = defaults.string(forKey: "host") ?? ""
        let port = NSTextField(frame: NSRect(x: 0, y: 29, width: 280, height: 24))
        port.placeholderString = "Port (default 24830)"
        if let p = UInt16(defaults.integer(forKey: "port")).nonZero { port.stringValue = String(p) }
        let secret = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        secret.placeholderString = "Pairing code, e.g. ABCDE-FGHIJ-KLMNO-PQRST"
        secret.stringValue = defaults.string(forKey: "secret") ?? ""
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 82))
        [host, port, secret].forEach(box.addSubview)
        alert.accessoryView = box
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = host
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let h = host.stringValue.trimmingCharacters(in: .whitespaces)
        let p = UInt16(port.stringValue.trimmingCharacters(in: .whitespaces)) ?? 24830
        let s = secret.stringValue.trimmingCharacters(in: .whitespaces)
        defaults.set(h, forKey: "host"); defaults.set(Int(p), forKey: "port"); defaults.set(s, forKey: "secret")
        if remote { setRemote(false) }
        link.connect(host: h, port: p, secret: s)
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func quit() {
        if remote { setRemote(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }
}

extension UInt16 { var nonZero: UInt16? { self == 0 ? nil : self } }

if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--selftest" {
    let a = CommandLine.arguments
    let multitouch = Multitouch()
    let link = Link()
    link.onStateChange = { st in
        switch st {
        case .connected:
            for scan: UInt16 in [0x23, 0x17] { link.sendKey(scan: scan, down: true); link.sendKey(scan: scan, down: false) }
            link.sendMove(dx: 25, dy: -7)
            link.sendButton(1, down: true); link.sendButton(1, down: false)
            link.sendWheel(v: -120, h: 40)
            link.sendPinch(0, scale: 1); link.sendPinch(1, scale: 1.75); link.sendPinch(1, scale: 0.4); link.sendPinch(2, scale: 0.4)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { print("selftest: sent"); exit(0) }
        case .failed(let why): print("selftest: failed: \(why)"); exit(1)
        default: break
        }
    }
    link.connect(host: a[2], port: UInt16(a[3]) ?? 24830, secret: a[4])
    dispatchMain()
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
