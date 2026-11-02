import Foundation

/// 并发探测端口可达性。只探 TCP，且由调用方决定探测范围（避免把系统端口全探一遍）。
public struct HealthChecker: Sendable {
    public init() {}

    public func probe(
        ports: [ListeningPort],
        timeout: TimeInterval = 0.6
    ) async -> [String: Reachability] {
        let targets = ports.filter { $0.proto == .tcp }
        guard !targets.isEmpty else { return [:] }

        var result: [String: Reachability] = [:]
        await withTaskGroup(of: (String, Reachability).self) { group in
            for port in targets {
                let address = port.address
                let portNumber = port.port
                let id = port.id
                group.addTask {
                    let ok = TCProbe.reachable(address: address, port: portNumber, timeout: timeout)
                    return (id, ok ? .reachable : .unreachable)
                }
            }
            for await pair in group {
                result[pair.0] = pair.1
            }
        }
        return result
    }
}