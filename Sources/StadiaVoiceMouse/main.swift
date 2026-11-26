import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

struct Options {
    var url = URL(string: "http://127.0.0.1/_events")!
    var controller: String?
    var voiceKeycode: CGKeyCode = 54 // right Command; set Doubao to the same hold shortcut
    var sendKeycode: CGKeyCode = 36 // Return; Telegram sends the composed message
    var keyboardInput = "Built-in Microphone"
    var controllerInput = "BlackHole 16ch"
    var speed = 1250.0 // points per second at full left-stick deflection
    var dryRun = false
    var selfTest = false
    var showSettings = false

    init() {
        let args = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < args.count {
            let flag = args[i]
            if flag == "--dry-run" { dryRun = true; i += 1; continue }
            if flag == "--self-test" { selfTest = true; i += 1; continue }
            if flag == "--settings" { showSettings = true; i += 1; continue }
            if flag == "--help" {
                print("Usage: stadia-voice-mouse [--settings] [--url http://127.0.0.1/_events] [--controller c0] [--voice-keycode 54] [--send-keycode 36] [--keyboard-input NAME] [--controller-input NAME] [--speed 1250] [--dry-run] [--self-test]")
                exit(0)
            }
            guard i + 1 < args.count else { fatalError("Missing value for \(flag)") }
            let value = args[i + 1]
            switch flag {
            case "--url":
                guard let parsed = URL(string: value), parsed.scheme == "http",
                      let host = parsed.host,
                      host == "localhost" || Host.current().addresses.contains(host) else {
                    fatalError("--url must be a local HTTP address")
                }
                url = parsed
            case "--controller": controller = value
            case "--voice-keycode":
                guard let number = UInt16(value) else { fatalError("Invalid voice keycode") }
                voiceKeycode = number
            case "--send-keycode":
                guard let number = UInt16(value) else { fatalError("Invalid send keycode") }
                sendKeycode = number
            case "--keyboard-input": keyboardInput = value
            case "--controller-input": controllerInput = value
            case "--speed":
                guard let number = Double(value), number > 0, number <= 4000 else { fatalError("Invalid speed") }
                speed = number
            default: fatalError("Unknown argument: \(flag)")
            }
            i += 2
        }
    }
}

@MainActor final class Bridge {
    let options: Options
    var pad: PadState?
    var lastUpdate = Date.distantPast
    var lastTick = Date()
    var leftDown = false
    var rightDown = false
    var voiceDown = false
    var assistantDown = false
    var sendDown = false
    var sendCount = 0
    var deleteDown = false
    var deleteCount = 0
    var captureDown = false
    var captureCount = 0
    var scrollRemainder = 0.0
    var l2Down = false
    var r2Down = false
    var extraDown: [ButtonAction: Bool] = [:]
    var config: AppConfig
    var configStamp: Date?
    var lastConfigCheck = Date.distantPast
    let audioInput: AudioInputSwitcher
    let micControl: MicControl
    var pttReady = false
    var lastPttTry = Date.distantPast

    init(_ options: Options) {
        self.options = options
        config = AppConfig.load()
        configStamp = (try? AppConfig.fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if configStamp == nil { config.pointerSpeed = options.speed }
        audioInput = AudioInputSwitcher(controllerName: options.controllerInput, keyboardName: options.keyboardInput)
        micControl = MicControl(host: options.url.host ?? "127.0.0.1", port: UInt16(options.url.port ?? 80), controller: options.controller ?? "c0")
        if !options.dryRun {
            lastPttTry = Date()
            pttReady = micControl.setPtt(false)
        }
        if !options.dryRun && !pttReady {
            fputs("Cannot disable Stadiacast push-to-talk. Voice toggle is unavailable.\n", stderr)
        }
    }

    func update(_ data: Data) {
        reloadConfig()
        let next = selectedPad(from: data, controller: options.controller)
        if next == nil { releaseAll() }
        pad = next
        lastUpdate = Date()
        syncButtons()
    }

    func tick() {
        reloadConfig()
        let now = Date()
        if !options.dryRun && !pttReady && now.timeIntervalSince(lastPttTry) >= 5 {
            lastPttTry = now
            pttReady = micControl.setPtt(false)
        }
        let dt = min(0.05, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now
        guard now.timeIntervalSince(lastUpdate) < 2.5, let pad else { releaseAll(); return }
        let (vx, vy) = stick(pad.lx, pad.ly)
        if vx != 0 || vy != 0, let location = CGEvent(source: nil)?.location {
            let point = CGPoint(x: location.x + vx * config.pointerSpeed * dt,
                                y: location.y - vy * config.pointerSpeed * dt)
            if options.dryRun { print("move \(Int(point.x)),\(Int(point.y))") }
            else { CGWarpMouseCursorPosition(point) }
        }
        let (_, sy) = stick(pad.rx, pad.ry)
        scrollRemainder += sy * config.scrollSpeed * dt
        let lines = Int(scrollRemainder.rounded(.towardZero))
        if lines != 0 {
            scrollRemainder -= Double(lines)
            if options.dryRun { print("scroll \(lines)") }
            else { CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(lines), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap) }
        }
    }

    func syncButtons() {
        let held = pad?.held ?? []
        l2Down = triggerPressed(pad?.l2 ?? 0, wasDown: l2Down)
        r2Down = triggerPressed(pad?.r2 ?? 0, wasDown: r2Down)
        setMouse(.left, down: active(.mouseLeft, held: held))
        setMouse(.right, down: active(.mouseRight, held: held))
        setAssistant(down: active(.voice, held: held))
        setSend(down: active(.enter, held: held))
        setDelete(down: active(.backspace, held: held))
        setCapture(down: active(.screenshot, held: held))
        for action in [ButtonAction.space, .escape, .tab, .arrowUp, .arrowDown, .arrowLeft, .arrowRight] {
            setExtra(action, down: active(action, held: held))
        }
    }

    func active(_ action: ButtonAction, held: Set<String>) -> Bool {
        config.mappings.contains { button, mapped in
            guard mapped == action else { return false }
            if button == "l2" { return l2Down }
            if button == "r2" { return r2Down }
            return held.contains(button)
        }
    }

    func reloadConfig() {
        let now = Date()
        guard now.timeIntervalSince(lastConfigCheck) >= 1 else { return }
        lastConfigCheck = now
        let stamp = (try? AppConfig.fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard stamp != configStamp else { return }
        releaseAll()
        config = AppConfig.load()
        if stamp == nil { config.pointerSpeed = options.speed }
        configStamp = stamp
    }

    func releaseAll() {
        pad = nil
        assistantDown = false
        if voiceDown { setVoice(active: false) }
        syncButtons()
        scrollRemainder = 0
    }

    func connectionLost() {
        releaseAll()
        pttReady = false
    }

    func stop() {
        releaseAll()
        if !options.dryRun {
            _ = micControl.setMicrophone(false)
            _ = audioInput.useKeyboard()
        }
    }

    enum MouseButton { case left, right }
    func setMouse(_ button: MouseButton, down: Bool) {
        let wasDown = button == .left ? leftDown : rightDown
        guard wasDown != down else { return }
        if button == .left { leftDown = down } else { rightDown = down }
        if options.dryRun { print("\(button) \(down ? "down" : "up")"); return }
        let eventType: CGEventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        let cgButton: CGMouseButton = button == .left ? .left : .right
        let location = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: location, mouseButton: cgButton)?.post(tap: .cghidEventTap)
    }

    func setAssistant(down: Bool) {
        guard assistantDown != down else { return }
        assistantDown = down
        if down { setVoice(active: !voiceDown) }
    }

    func setVoice(active: Bool) {
        guard voiceDown != active else { return }
        if options.dryRun {
            voiceDown = active
            print("voice \(active ? "on" : "off")")
            return
        }
        if active {
            guard audioInput.useController() else { return }
            lastPttTry = Date()
            pttReady = micControl.setPtt(false)
            guard pttReady, micControl.setMicrophone(true) else {
                fputs("Cannot start controller microphone; voice shortcut was not sent.\n", stderr)
                _ = audioInput.useKeyboard()
                return
            }
            voiceDown = true
            tapVoiceShortcut()
        } else {
            tapVoiceShortcut()
            voiceDown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !self.voiceDown else { return }
                _ = self.micControl.setMicrophone(false)
                _ = self.audioInput.useKeyboard()
            }
        }
    }

    func tapVoiceShortcut() {
        voiceEvent(keycode: options.voiceKeycode, down: true)?.post(tap: .cghidEventTap)
        usleep(80_000)
        voiceEvent(keycode: options.voiceKeycode, down: false)?.post(tap: .cghidEventTap)
    }

    func setSend(down: Bool) {
        defer { sendDown = down }
        guard down && !sendDown else { return }
        sendCount += 1
        if options.dryRun { print("send tap"); return }
        CGEvent(keyboardEventSource: nil, virtualKey: options.sendKeycode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: options.sendKeycode, keyDown: false)?.post(tap: .cghidEventTap)
    }

    func setDelete(down: Bool) {
        defer { deleteDown = down }
        guard down && !deleteDown else { return }
        deleteCount += 1
        if options.dryRun { print("delete tap"); return }
        CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false)?.post(tap: .cghidEventTap)
    }

    func setCapture(down: Bool) {
        defer { captureDown = down }
        guard down && !captureDown else { return }
        captureCount += 1
        if options.dryRun { print("capture tap"); return }
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        for pressed in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 23, keyDown: pressed) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    func setExtra(_ action: ButtonAction, down: Bool) {
        let wasDown = extraDown[action] ?? false
        extraDown[action] = down
        guard down && !wasDown, let keycode = action.keycode else { return }
        if options.dryRun { print("\(action.rawValue) tap"); return }
        CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: false)?.post(tap: .cghidEventTap)
    }
}

func voiceEvent(keycode: CGKeyCode, down: Bool) -> CGEvent? {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: down) else { return nil }
    if keycode == 54 || keycode == 55 { // right or left Command
        event.type = .flagsChanged
        event.flags = down ? .maskCommand : []
    }
    return event
}

final class EventStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let options: Options
    let bridge: Bridge
    var parser = SSEParser()
    var session: URLSession?
    var task: URLSessionDataTask?

    init(options: Options, bridge: Bridge) { self.options = options; self.bridge = bridge }

    func start() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: options.url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        task = session?.dataTask(with: request)
        task?.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let messages = parser.feed(String(decoding: data, as: UTF8.self))
        for message in messages { Task { @MainActor in bridge.update(message) } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in bridge.connectionLost() }
        print("Event stream disconnected: \(error?.localizedDescription ?? "closed"); reconnecting")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }
}

let options = Options()
if options.showSettings {
    runSettingsWindow()
    exit(0)
}
if options.selfTest {
    let defaultConfig = AppConfig()
    let encodedConfig = try! JSONEncoder().encode(defaultConfig)
    let decodedConfig = try! JSONDecoder().decode(AppConfig.self, from: encodedConfig)
    precondition(decodedConfig.mappings["l2"] == .voice)
    precondition(decodedConfig.mappings["r2"] == .enter)
    precondition(decodedConfig.mappings["capture"] == .screenshot)
    var parser = SSEParser()
    precondition(parser.feed("event: input\ndata: {\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"input\":{\"lx\":12000,\"ly\":0,\"held\":[\"assistant\"],\"age_s\":0}}}}").isEmpty)
    let events = parser.feed("\n\n")
    precondition(events.count == 1)
    precondition(selectedPad(from: events[0], controller: "c0")?.held.contains("assistant") == true)
    precondition(stick(1000, 1000).0 == 0)
    precondition(stick(30000, 0).0 > 0.5)
    precondition(!triggerPressed(159, wasDown: false))
    precondition(triggerPressed(160, wasDown: false))
    precondition(triggerPressed(80, wasDown: true))
    precondition(!triggerPressed(79, wasDown: true))
    precondition(voiceEvent(keycode: 54, down: true)?.type == .flagsChanged)
    precondition(voiceEvent(keycode: 54, down: true)?.flags.contains(.maskCommand) == true)
    precondition(voiceEvent(keycode: 54, down: false)?.flags.contains(.maskCommand) == false)
    precondition(voiceEvent(keycode: 36, down: true)?.type == .keyDown)
    let stale = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":6,\"input\":{\"age_s\":5}}}}".utf8)
    precondition(selectedPad(from: stale, controller: nil) == nil)
    var testOptions = Options()
    testOptions.dryRun = true
    let testBridge = Bridge(testOptions)
    let held = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"assistant\",\"a\"]}}}}".utf8)
    testBridge.update(held)
    precondition(testBridge.voiceDown && testBridge.leftDown)
    let released = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[]}}}}".utf8)
    testBridge.update(released)
    precondition(testBridge.voiceDown && !testBridge.assistantDown)
    testBridge.update(held)
    precondition(!testBridge.voiceDown && testBridge.assistantDown)
    testBridge.releaseAll()
    precondition(!testBridge.voiceDown && !testBridge.leftDown)
    let l2 = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"l2\":210}}}}".utf8)
    testBridge.update(l2)
    precondition(testBridge.voiceDown)
    testBridge.update(l2)
    precondition(testBridge.voiceDown)
    testBridge.update(released)
    testBridge.update(l2)
    precondition(!testBridge.voiceDown)
    testBridge.releaseAll()
    let send = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"x\"]}}}}".utf8)
    testBridge.update(send)
    testBridge.update(send)
    precondition(testBridge.sendCount == 1)
    testBridge.update(released)
    let r2 = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"r2\":210}}}}".utf8)
    testBridge.update(r2)
    testBridge.update(r2)
    precondition(testBridge.sendCount == 2)
    testBridge.update(released)
    let y = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"y\"]}}}}".utf8)
    testBridge.update(y)
    testBridge.update(y)
    precondition(testBridge.deleteCount == 1)
    testBridge.update(released)
    let capture = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"capture\"]}}}}".utf8)
    testBridge.update(capture)
    testBridge.update(capture)
    precondition(testBridge.captureCount == 1)
    testBridge.releaseAll()
    testBridge.update(held)
    let voiceAndSend = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"assistant\",\"x\"]}}}}".utf8)
    testBridge.update(voiceAndSend)
    precondition(testBridge.sendCount == 3)
    testBridge.update(released)
    testBridge.update(y)
    precondition(testBridge.deleteCount == 2)
    testBridge.releaseAll()
    print("PASS: SSE parsing, pad selection, deadzone, trigger thresholds, stale connection, voice toggle, button release, send, delete and capture taps")
    exit(0)
}
if !options.dryRun && !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
    fputs("Grant Accessibility permission in System Settings, then run again.\n", stderr)
    exit(1)
}
let bridge = Bridge(options)
let stream = EventStream(options: options, bridge: bridge)
stream.start()
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler { bridge.stop(); exit(0) }
interrupt.resume()
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { bridge.stop(); exit(0) }
terminate.resume()
Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
    Task { @MainActor in bridge.tick() }
}
print("Listening to \(options.url.absoluteString); controller \(options.controller ?? "first available")")
if Bundle.main.bundleURL.pathExtension == "app" {
    NSApplication.shared.setActivationPolicy(.prohibited)
    NSApplication.shared.run()
} else {
    RunLoop.main.run()
}
