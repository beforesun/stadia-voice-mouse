import Foundation
import ApplicationServices
import CoreGraphics
import Darwin

struct Options {
    var url = URL(string: "http://127.0.0.1/_events")!
    var controller: String?
    var voiceKeycode: CGKeyCode = 54 // right Command; set Doubao to the same hold shortcut
    var sendKeycode: CGKeyCode = 36 // Return; Telegram sends the composed message
    var speed = 1250.0 // points per second at full left-stick deflection
    var dryRun = false
    var selfTest = false

    init() {
        let args = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < args.count {
            let flag = args[i]
            if flag == "--dry-run" { dryRun = true; i += 1; continue }
            if flag == "--self-test" { selfTest = true; i += 1; continue }
            if flag == "--help" {
                print("Usage: stadia-voice-mouse [--url http://127.0.0.1/_events] [--controller c0] [--voice-keycode 54] [--send-keycode 36] [--speed 1250] [--dry-run] [--self-test]")
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
    var sendDown = false
    var sendCount = 0
    var scrollRemainder = 0.0

    init(_ options: Options) { self.options = options }

    func update(_ data: Data) {
        let next = selectedPad(from: data, controller: options.controller)
        if next == nil { releaseAll() }
        pad = next
        lastUpdate = Date()
        syncButtons()
    }

    func tick() {
        let now = Date()
        let dt = min(0.05, max(0, now.timeIntervalSince(lastTick)))
        lastTick = now
        guard now.timeIntervalSince(lastUpdate) < 2.5, let pad else { releaseAll(); return }
        let (vx, vy) = stick(pad.lx, pad.ly)
        if vx != 0 || vy != 0, let location = CGEvent(source: nil)?.location {
            let point = CGPoint(x: location.x + vx * options.speed * dt,
                                y: location.y - vy * options.speed * dt)
            if options.dryRun { print("move \(Int(point.x)),\(Int(point.y))") }
            else { CGWarpMouseCursorPosition(point) }
        }
        let (_, sy) = stick(pad.rx, pad.ry)
        scrollRemainder += sy * 28 * dt
        let lines = Int(scrollRemainder.rounded(.towardZero))
        if lines != 0 {
            scrollRemainder -= Double(lines)
            if options.dryRun { print("scroll \(lines)") }
            else { CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(lines), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap) }
        }
    }

    func syncButtons() {
        let held = pad?.held ?? []
        setMouse(.left, down: held.contains("a"))
        setMouse(.right, down: held.contains("b"))
        setVoice(down: held.contains("assistant"))
        setSend(down: held.contains("x"))
    }

    func releaseAll() {
        pad = nil
        syncButtons()
        scrollRemainder = 0
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

    func setVoice(down: Bool) {
        guard voiceDown != down else { return }
        voiceDown = down
        if options.dryRun { print("voice \(down ? "down" : "up")"); return }
        CGEvent(keyboardEventSource: nil, virtualKey: options.voiceKeycode, keyDown: down)?.post(tap: .cghidEventTap)
    }

    func setSend(down: Bool) {
        defer { sendDown = down }
        guard down && !sendDown && !voiceDown else { return }
        sendCount += 1
        if options.dryRun { print("send tap"); return }
        CGEvent(keyboardEventSource: nil, virtualKey: options.sendKeycode, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: options.sendKeycode, keyDown: false)?.post(tap: .cghidEventTap)
    }
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
        Task { @MainActor in bridge.releaseAll() }
        print("Event stream disconnected: \(error?.localizedDescription ?? "closed"); reconnecting")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }
}

let options = Options()
if options.selfTest {
    var parser = SSEParser()
    precondition(parser.feed("event: input\ndata: {\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"input\":{\"lx\":12000,\"ly\":0,\"held\":[\"assistant\"],\"age_s\":0}}}}").isEmpty)
    let events = parser.feed("\n\n")
    precondition(events.count == 1)
    precondition(selectedPad(from: events[0], controller: "c0")?.held.contains("assistant") == true)
    precondition(stick(1000, 1000).0 == 0)
    precondition(stick(30000, 0).0 > 0.5)
    let stale = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":6,\"input\":{\"age_s\":5}}}}".utf8)
    precondition(selectedPad(from: stale, controller: nil) == nil)
    var testOptions = Options()
    testOptions.dryRun = true
    let testBridge = Bridge(testOptions)
    let held = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"assistant\",\"a\"]}}}}".utf8)
    testBridge.update(held)
    precondition(testBridge.voiceDown && testBridge.leftDown)
    testBridge.releaseAll()
    precondition(!testBridge.voiceDown && !testBridge.leftDown)
    let send = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"x\"]}}}}".utf8)
    testBridge.update(send)
    testBridge.update(send)
    precondition(testBridge.sendCount == 1)
    testBridge.releaseAll()
    testBridge.update(held)
    let voiceAndSend = Data("{\"controllers\":{\"c0\":{\"display_state\":\"ready\",\"last_seen_s\":0,\"input\":{\"held\":[\"assistant\",\"x\"]}}}}".utf8)
    testBridge.update(voiceAndSend)
    precondition(testBridge.sendCount == 1)
    testBridge.releaseAll()
    print("PASS: SSE parsing, pad selection, deadzone, stale connection, button release, send tap")
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
interrupt.setEventHandler { bridge.releaseAll(); exit(0) }
interrupt.resume()
let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminate.setEventHandler { bridge.releaseAll(); exit(0) }
terminate.resume()
Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
    Task { @MainActor in bridge.tick() }
}
print("Listening to \(options.url.absoluteString); controller \(options.controller ?? "first available")")
RunLoop.main.run()
