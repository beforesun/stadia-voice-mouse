import Foundation
import SwiftUI

@MainActor
struct StatusPanel: View {
    @State private var receiver = "正在检查接收器…"
    @State private var controller = "手柄：待检查"
    @State private var microphone = "麦克风：待检查"
    @State private var bridge = "按键程序：待检查"
    @State private var detail = ""
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(receiver).font(.headline)
            HStack(spacing: 16) {
                Text(controller)
                Text(microphone)
                Text(bridge)
            }
            .font(.caption)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .task { await refresh() }
        .onReceive(refreshTimer) { _ in Task { await refresh() } }
    }

    private func refresh() async {
        bridge = bridgeRunning() ? "按键程序：运行中" : "按键程序：未运行"
        let addresses = Host.current().addresses.filter { address in
            address == "127.0.0.1" || address.hasPrefix("192.168.") || address.hasPrefix("10.")
        }.sorted { left, right in
            if left == "127.0.0.1" { return false }
            if right == "127.0.0.1" { return true }
            return left < right
        }
        for address in addresses {
            guard let url = URL(string: "http://\(address)/_status") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.5
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["version"] is String,
                  let controllers = root["controllers"] as? [String: [String: Any]] else { continue }
            receiver = "接收器：运行中（\(address)）"
            if let (label, state) = controllers.first {
                let age = state["last_seen_s"] as? Double ?? 999
                let connected = age < 5
                controller = connected ? "手柄 \(label)：已连接" : "手柄 \(label)：连接中断"
                if let battery = state["battery_percent"] as? Int, connected {
                    controller += " · 电量 \(battery)%"
                }
                let mic = state["microphone"] as? [String: Any]
                microphone = (mic?["on"] as? Bool == true) ? "麦克风：开启" : "麦克风：关闭"
                detail = connected ? "" : "检查手柄 Wi-Fi、路由器 DNS 和接收器日志。"
            } else {
                controller = "手柄：未连接"
                microphone = "麦克风：关闭"
                detail = "检查手柄 Wi-Fi 和路由器中的手柄专用 DNS。"
            }
            if let device = root["mic_device"] as? [String: Any], let error = device["error"] as? String, !error.isEmpty {
                detail = "音频设备：\(error)"
            }
            return
        }
        receiver = "接收器：未运行或无法访问"
        controller = "手柄：状态未知"
        microphone = "麦克风：状态未知"
        detail = "检查 stadiacast 后台服务；也可能是本机 IP 地址已变化。"
    }

    private func bridgeRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "/stadia-voice-mouse --url"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }
}
