import Foundation
import Darwin

/// 纯 TCP 握手探测。
///
/// 为什么不用 HTTP：MySQL / Redis / gRPC 服务收到 HTTP 请求会直接挂断或超时，
/// 用 HTTP 判定会把「活着但不讲 HTTP」的服务误报为不可达。TCP 握手才等价于端口可用。
public enum TCProbe {
    public static func reachable(address: String, port: Int, timeout: TimeInterval = 0.6) -> Bool {
        for host in hosts(for: address) {
            if connectOnce(host: host, port: port, timeout: timeout) {
                return true
            }
        }
        return false
    }

    static func hosts(for address: String) -> [String] {
        switch address {
        case "*", "0.0.0.0", "127.0.0.1", "localhost":
            // 通配监听可能只绑了 IPv4 或 IPv6，两个都试
            return ["127.0.0.1", "::1"]
        case "::", "::1":
            return ["::1"]
        default:
            return [address]
        }
    }

    private static func connectOnce(host: String, port: Int, timeout: TimeInterval) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var infoPointer: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &infoPointer) == 0, let head = infoPointer else {
            return false
        }
        defer { freeaddrinfo(head) }

        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let addressInfo = cursor {
            let ai = addressInfo.pointee
            let fd = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
            if fd >= 0 {
                if handshake(fd: fd, addr: ai.ai_addr, len: ai.ai_addrlen, timeout: timeout) {
                    close(fd)
                    return true
                }
                close(fd)
            }
            cursor = ai.ai_next
        }
        return false
    }

    private static func handshake(
        fd: Int32,
        addr: UnsafeMutablePointer<sockaddr>,
        len: socklen_t,
        timeout: TimeInterval
    ) -> Bool {
        let originalFlags = fcntl(fd, F_GETFL, 0)
        guard originalFlags >= 0, fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) >= 0 else {
            return false
        }

        let result = Darwin.connect(fd, addr, len)
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let milliseconds = Int32(max(timeout, 0.05) * 1000)
        let ready = poll(&pollDescriptor, 1, milliseconds)
        guard ready > 0 else { return false }

        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else {
            return false
        }
        return socketError == 0
    }
}