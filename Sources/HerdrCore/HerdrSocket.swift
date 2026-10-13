import Foundation
import Darwin

public enum SocketError: LocalizedError {
    case system(String), invalidPath, timeout, invalidResponse, remote(String), oversized
    public var errorDescription: String? {
        switch self {
        case .system(let s), .remote(let s): return s
        case .invalidPath: return "Herdr socket 路径过长"
        case .timeout: return "Herdr 响应超时"
        case .invalidResponse: return "Herdr 返回了无效数据"
        case .oversized: return "Herdr 响应超过大小限制"
        }
    }
}

/// Herdr serves one newline-delimited request per connection. No subprocess,
/// transcript access, network listener, or agent-specific hook is required.
public enum HerdrSocket {
    public static func request(path: String, method: String, params: [String: Any] = [:]) throws -> Data {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(String(cString: strerror(errno))) }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw SocketError.invalidPath }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw SocketError.system(String(cString: strerror(errno))) }
        var request = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "method": method, "params": params])
        request.append(10)
        try request.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Darwin.send(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SocketError.system("无法发送 Herdr 请求") }
                sent += count
            }
        }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        let deadline = Date().addingTimeInterval(3)
        while true {
            guard Date() < deadline else { throw SocketError.timeout }
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { throw SocketError.timeout }
            guard count > 0 else { throw SocketError.invalidResponse }
            response.append(contentsOf: buffer.prefix(count))
            guard response.count < 4 * 1024 * 1024 else { throw SocketError.oversized }
            if let end = response.firstIndex(of: 10) { response = response.prefix(upTo: end); break }
        }
        guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any] else { throw SocketError.invalidResponse }
        if let error = json["error"] as? [String: Any] { throw SocketError.remote(error["message"] as? String ?? "Herdr 请求失败") }
        guard json["result"] != nil else { throw SocketError.invalidResponse }
        return response
    }

    public static func discover(root: String = NSHomeDirectory() + "/.config/herdr") -> [String] {
        var paths: Set<String> = []
        if let explicit = ProcessInfo.processInfo.environment["HERDR_TOUCHBAR_SOCKET"] { paths.insert(explicit) }
        let defaultSocket = root + "/herdr.sock"
        if FileManager.default.fileExists(atPath: defaultSocket) { paths.insert(defaultSocket) }
        if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if enumerator.level > 4 { enumerator.skipDescendants(); continue }
                if url.lastPathComponent == "herdr.sock" { paths.insert(url.path) }
            }
        }
        return paths.sorted()
    }
    public static func sessionName(for socket: String) -> String {
        let directory = URL(fileURLWithPath: socket).deletingLastPathComponent()
        return directory.lastPathComponent == "herdr" ? "default" : directory.lastPathComponent
    }
}
