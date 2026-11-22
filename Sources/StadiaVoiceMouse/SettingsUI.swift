import AppKit
import SwiftUI

private final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor private let settingsAppDelegate = SettingsAppDelegate()

@MainActor
private struct SettingsView: View {
    @State private var config = AppConfig.load()
    @State private var message = "修改后点击“保存设置”，运行中的手柄程序会自动更新。"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stadia 手柄按键设置")
                .font(.title2.bold())
            Text("选择每个按键在 Mac 上执行的动作。语音输入仍使用豆包的右 Command 快捷键。")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ControllerButton.all) { button in
                        HStack {
                            Text(button.title)
                                .frame(width: 150, alignment: .leading)
                            Picker(button.title, selection: Binding(
                                get: { config.mappings[button.id] ?? ButtonAction.none },
                                set: { config.mappings[button.id] = $0 }
                            )) {
                                ForEach(ButtonAction.allCases) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("鼠标速度")
                Slider(value: $config.pointerSpeed, in: 300...3000, step: 50)
                Text("\(Int(config.pointerSpeed))")
                    .monospacedDigit()
                    .frame(width: 48)
            }
            HStack {
                Text("滚动速度")
                Slider(value: $config.scrollSpeed, in: 5...80, step: 1)
                Text("\(Int(config.scrollSpeed))")
                    .monospacedDigit()
                    .frame(width: 48)
            }
            HStack {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") { config = AppConfig(); message = "默认设置已载入，点击“保存设置”后生效。" }
                Button("保存设置") {
                    do {
                        try config.save()
                        message = "已保存，手柄程序将在约 1 秒内更新。"
                    } catch {
                        message = "保存失败：\(error.localizedDescription)"
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 660)
    }
}

@MainActor
func runSettingsWindow() {
    let app = NSApplication.shared
    app.delegate = settingsAppDelegate
    app.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Stadia 手柄设置"
    window.contentView = NSHostingView(rootView: SettingsView())
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}
