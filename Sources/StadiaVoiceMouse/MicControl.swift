import Darwin
import Foundation

struct MicControl {
    let host: String
    let port: UInt16
    let controller: String

    func setPtt(_ enabled: Bool) -> Bool { post(["do": "ptt", "on": enabled]) }
    func setMicrophone(_ enabled: Bool) -> Bool { post(["do": enabled ? "on" : "off"]) }

    private func post(_ action: [String: Any]) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        guard inet_pton(AF_INET, "127.0.0.1", &local.sin_addr) == 1 else { return false }
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return false }

        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &remote.sin_addr) }) == 1 else { return false }
        let connected = withUnsafePointer(to: &remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return false }

        var body = action
        body["controller"] = controller
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }
        let header = "POST /_mic HTTP/1.1\r\nHost: \(host)\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var request = Data(header.utf8)
        request.append(payload)
        let sent = request.withUnsafeBytes { bytes in Darwin.send(fd, bytes.baseAddress, bytes.count, 0) }
        guard sent == request.count else { return false }
        var response = [UInt8](repeating: 0, count: 2048)
        let count = Darwin.recv(fd, &response, response.count, 0)
        guard count > 0, let line = String(bytes: response[..<count], encoding: .utf8)?.components(separatedBy: "\r\n").first else { return false }
        return line.hasPrefix("HTTP/1.1 200 ") || line.hasPrefix("HTTP/1.0 200 ")
    }
}
