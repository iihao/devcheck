import Foundation

/// 体检规则引擎：纯函数，输入端口列表，输出告警列表。
/// 规则新增只需往 `evaluate` 里加一段，UI 与 CLI 自动生效。
public enum RuleEngine {
    public static let highCPUThreshold: Double = 80

    public static func evaluate(ports: [ListeningPort]) -> [Issue] {
        var issues: [Issue] = []
        issues += duplicatePortIssues(ports)
        issues += unreachableIssues(ports)
        issues += highCPUIssues(ports)
        return issues.sorted { $0.severity > $1.severity }
    }

    // MARK: - 同一端口多进程

    static func duplicatePortIssues(_ ports: [ListeningPort]) -> [Issue] {
        var buckets: [Int: [ListeningPort]] = [:]
        for port in ports where port.proto == .tcp {
            buckets[port.port, default: []].append(port)
        }

        return buckets.compactMap { portNumber, group in
            let pids = Set(group.map(\.pid))
            guard pids.count > 1 else { return nil }
            let commands = Set(group.map(\.command)).sorted().joined(separator: ", ")
            return Issue(
                kind: .duplicatePort,
                severity: .warning,
                subject: "\(portNumber)",
                message: L("端口 \(portNumber) 被 \(pids.count) 个进程同时占用：\(commands)",
                           "Port \(portNumber) is held by \(pids.count) processes: \(commands)"),
                portIDs: group.map(\.id)
            )
        }
    }

    // MARK: - 只监不听

    static func unreachableIssues(_ ports: [ListeningPort]) -> [Issue] {
        ports.compactMap { port in
            guard port.reachability == .unreachable, !port.isNoise else { return nil }
            return Issue(
                kind: .unreachable,
                severity: .warning,
                subject: "\(port.port)",
                message: L("\(port.command)（PID \(port.pid)）在监听 \(port.port)，但 TCP 握手失败，可能已僵死",
                           "\(port.command) (PID \(port.pid)) listens on \(port.port) but the TCP handshake fails — possibly hung"),
                portIDs: [port.id]
            )
        }
    }

    // MARK: - CPU 过高

    static func highCPUIssues(_ ports: [ListeningPort]) -> [Issue] {
        ports.compactMap { port in
            guard let cpu = port.cpuPercent, cpu > highCPUThreshold, !port.isNoise else { return nil }
            return Issue(
                kind: .highCPU,
                severity: .warning,
                subject: "\(port.command)-\(port.pid)",
                message: L("\(port.command)（PID \(port.pid)，端口 \(port.port)）CPU \(Int(cpu))%",
                           "\(port.command) (PID \(port.pid), port \(port.port)) is using \(Int(cpu))% CPU"),
                portIDs: [port.id]
            )
        }
    }
}