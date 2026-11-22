import Foundation

struct PadState: Equatable {
    var lx: Int = 0
    var ly: Int = 0
    var rx: Int = 0
    var ry: Int = 0
    var l2: Int = 0
    var r2: Int = 0
    var held: Set<String> = []

    init(_ value: [String: Any]) {
        lx = value["lx"] as? Int ?? 0
        ly = value["ly"] as? Int ?? 0
        rx = value["rx"] as? Int ?? 0
        ry = value["ry"] as? Int ?? 0
        l2 = value["l2"] as? Int ?? 0
        r2 = value["r2"] as? Int ?? 0
        held = Set(value["held"] as? [String] ?? [])
    }

    init() {}
}

func selectedPad(from data: Data, controller: String?) -> PadState? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let controllers = root["controllers"] as? [String: [String: Any]] else { return nil }
    let entry: [String: Any]?
    if let controller {
        entry = controllers[controller]
    } else {
        entry = controllers.sorted { $0.key < $1.key }.map(\.value).first {
            $0["input"] is [String: Any] &&
            ($0["display_state"] as? String == "ready" || $0["display_state"] as? String == "input")
        }
    }
    guard let entry, let input = entry["input"] as? [String: Any],
          (entry["display_state"] as? String == "ready" || entry["display_state"] as? String == "input"),
          (entry["last_seen_s"] as? Double ?? 0) < 5 else { return nil }
    return PadState(input)
}

func stick(_ x: Int, _ y: Int, deadzone: Double = 0.16) -> (Double, Double) {
    let nx = max(-1, min(1, Double(x) / 32767))
    let ny = max(-1, min(1, Double(y) / 32767))
    let radius = hypot(nx, ny)
    guard radius > deadzone else { return (0, 0) }
    let magnitude = pow(min(1, (radius - deadzone) / (1 - deadzone)), 1.7)
    return (nx / radius * magnitude, ny / radius * magnitude)
}

func triggerPressed(_ value: Int, wasDown: Bool) -> Bool {
    value >= (wasDown ? 80 : 160)
}

struct SSEParser {
    private var buffer = ""
    private var eventData: [String] = []

    mutating func feed(_ chunk: String) -> [Data] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        var output: [Data] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            if line.isEmpty {
                if !eventData.isEmpty {
                    output.append(Data(eventData.joined(separator: "\n").utf8))
                    eventData.removeAll()
                }
            } else if line.hasPrefix("data:") {
                eventData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        return output
    }
}
