import Foundation

/// 通过 `lsof -F` 的可解析输出采集监听端口。
///
/// 输出格式（每行首字符为字段类型）：
/// ```
/// p705          <- PID
/// crapportd     <- COMMAND
/// u501          <- UID
/// f11           <- 文件描述符
/// PTCP          <- 协议
/// n*:49153      <- 地址:端口
/// ```
public enum PortCollector {
    public enum CollectError: Error {
        case unsupportedProtocol(TransportProtocol)
    }

    /// 采集所有 TCP LISTEN（可选 UDP）端口。
    public static func collect(includeUDP: Bool = false) throws -> [RawBinding] {
        var bindings = (try? collect(.tcp)) ?? []
        if includeUDP {
            bindings += (try? collect(.udp)) ?? []
        }
        return dedupe(bindings)
    }

    static func collect(_ proto: TransportProtocol) throws -> [RawBinding] {
        var arguments = ["-nP"]
        switch proto {
        case .tcp:
            arguments += ["-iTCP", "-sTCP:LISTEN"]
        case .udp:
            arguments += ["-iUDP"]
        }
        arguments.append("-FpcPnu")

        let output = try Shell.run("/usr/sbin/lsof", arguments)
        return parseBindings(output, proto: proto)
    }

    // MARK: - 解析

    /// 解析 `lsof -FpcPnu` 输出。公开以便单测。
    public static func parseBindings(_ text: String, proto: TransportProtocol) -> [RawBinding] {
        var result: [RawBinding] = []
        var currentPID: Int32?
        var currentCommand = ""
        var currentUID: UInt32 = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPID = Int32(value)
                currentCommand = ""
                currentUID = 0
            case "c":
                currentCommand = value
            case "u":
                currentUID = UInt32(value) ?? 0
            case "n":
                guard let pid = currentPID, let parsed = parseName(value) else { continue }
                result.append(
                    RawBinding(
                        pid: pid,
                        command: currentCommand,
                        uid: currentUID,
                        proto: proto,
                        address: parsed.address,
                        port: parsed.port
                    )
                )
            default:
                continue
            }
        }
        return result
    }

    /// 解析 `*:49153` / `127.0.0.1:3000` / `[::1]:8080` 形式的地址。
    public static func parseName(_ name: String) -> (address: String, port: Int)? {
        var address: String
        var portPart: String

        if name.hasPrefix("[") {
            guard let closing = name.lastIndex(of: "]") else { return nil }
            address = String(name[name.index(after: name.startIndex)..<closing])
            let rest = name[name.index(after: closing)...]
            guard rest.hasPrefix(":") else { return nil }
            portPart = String(rest.dropFirst())
        } else {
            guard let colon = name.lastIndex(of: ":") else { return nil }
            address = String(name[..<colon])
            portPart = String(name[name.index(after: colon)...])
        }

        guard let port = Int(portPart), port > 0, port <= 65535 else { return nil }
        if address.isEmpty { address = "*" }
        return (address, port)
    }

    // MARK: - 去重

    /// 同一进程同一端口可能出现 IPv4/IPv6 两条记录，按「越通配越优先」保留一条。
    static func dedupe(_ items: [RawBinding]) -> [RawBinding] {
        func rank(_ address: String) -> Int {
            switch address {
            case "*": return 0
            case "0.0.0.0": return 1
            case "::": return 2
            default: return 3
            }
        }

        var best: [String: RawBinding] = [:]
        for item in items {
            let key = "\(item.proto.rawValue)-\(item.pid)-\(item.port)"
            if let existing = best[key], rank(existing.address) <= rank(item.address) {
                continue
            }
            best[key] = item
        }
        return best.values.sorted {
            $0.port == $1.port ? $0.pid < $1.pid : $0.port < $1.port
        }
    }
}