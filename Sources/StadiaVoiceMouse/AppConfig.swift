import Foundation

enum ButtonAction: String, Codable, CaseIterable, Identifiable {
    case none, mouseLeft, mouseRight, voice, enter, backspace, screenshot
    case space, escape, tab, arrowUp, arrowDown, arrowLeft, arrowRight

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "不映射"
        case .mouseLeft: "鼠标左键"
        case .mouseRight: "鼠标右键"
        case .voice: "语音输入开关"
        case .enter: "Enter／发送"
        case .backspace: "退格删除"
        case .screenshot: "macOS 截图工具"
        case .space: "空格"
        case .escape: "Esc"
        case .tab: "Tab"
        case .arrowUp: "方向键 ↑"
        case .arrowDown: "方向键 ↓"
        case .arrowLeft: "方向键 ←"
        case .arrowRight: "方向键 →"
        }
    }

    var keycode: UInt16? {
        switch self {
        case .enter: 36
        case .backspace: 51
        case .space: 49
        case .escape: 53
        case .tab: 48
        case .arrowUp: 126
        case .arrowDown: 125
        case .arrowLeft: 123
        case .arrowRight: 124
        default: nil
        }
    }
}

struct ControllerButton: Identifiable {
    let id: String
    let title: String
    static let all: [ControllerButton] = [
        .init(id: "a", title: "A"), .init(id: "b", title: "B"),
        .init(id: "x", title: "X"), .init(id: "y", title: "Y"),
        .init(id: "l1", title: "L1"), .init(id: "r1", title: "R1"),
        .init(id: "l2", title: "L2"), .init(id: "r2", title: "R2"),
        .init(id: "assistant", title: "Assistant／语音键"),
        .init(id: "capture", title: "Capture／截图键"),
        .init(id: "dpad_up", title: "方向十字键 ↑"),
        .init(id: "dpad_down", title: "方向十字键 ↓"),
        .init(id: "dpad_left", title: "方向十字键 ←"),
        .init(id: "dpad_right", title: "方向十字键 →"),
        .init(id: "l3", title: "按下左摇杆 L3"),
        .init(id: "r3", title: "按下右摇杆 R3"),
        .init(id: "menu", title: "菜单键 ≡"),
        .init(id: "options", title: "选项键 ⋯"),
        .init(id: "stadia", title: "Stadia 键"),
    ]
}

struct AppConfig: Codable {
    var mappings: [String: ButtonAction] = [
        "a": .mouseLeft, "b": .mouseRight,
        "x": .enter, "r2": .enter, "y": .backspace, "r1": .escape,
        "assistant": .voice, "l2": .voice, "capture": .screenshot,
    ]
    var pointerSpeed = 1250.0
    var scrollSpeed = 28.0

    static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StadiaVoiceMouse", isDirectory: true)
        return folder.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return AppConfig() }
        return config
    }

    func save() throws {
        let url = Self.fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
