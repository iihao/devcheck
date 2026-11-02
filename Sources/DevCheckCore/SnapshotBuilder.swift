import Foundation

public struct SnapshotOptions: Sendable {
    /// 是否包含 UDP 端口
    public var includeUDP: Bool = false
    /// 是否做 TCP 可达性探测
    public var probe: Bool = true
    /// 单次探测超时
    public var probeTimeout: TimeInterval = 0.6
    /// 单次刷新最多探测多少个端口（防止误伤性能）
    public var maxProbePorts: Int = 40

    public init() {}
}

/// 一次刷新 = 一个不可变 Snapshot。
/// UI（菜单栏 / CLI / 未来 Web 面板）只消费 Snapshot，不关心采集细节。
public struct SnapshotBuilder: Sendable {
    private let resolver: ProjectResolver

    public init(resolver: ProjectResolver = ProjectResolver()) {
        self.resolver = resolver
    }

    public func build(options: SnapshotOptions = SnapshotOptions()) async -> Snapshot {
        let startedAt = Date()

        let bindings = (try? PortCollector.collect(includeUDP: options.includeUDP)) ?? []
        let pids = Array(Set(bindings.map(\.pid)))

        let workingDirectories = ProcessInfoCollector.workingDirectories(for: pids)
        let stats = ProcessInfoCollector.stats(for: pids)

        var ports: [ListeningPort] = bindings.map { raw in
            let cwd = workingDirectories[raw.pid]
            let project = cwd.flatMap { resolver.resolve(cwd: $0) }
            return ListeningPort(
                raw: raw,
                cwd: cwd,
                project: project,
                stat: stats[raw.pid]
            )
        }

        if options.probe {
            let targets = probeTargets(from: ports, limit: options.maxProbePorts)
            let reachability = await HealthChecker().probe(ports: targets, timeout: options.probeTimeout)
            ports = ports.map { port in
                var copy = port
                copy.reachability = reachability[port.id] ?? .unknown
                return copy
            }
        }

        let issues = RuleEngine.evaluate(ports: ports)
        let system = SystemProbe.current()
        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)

        return Snapshot(
            generatedAt: Date(),
            durationMs: duration,
            ports: ports,
            issues: issues,
            system: system
        )
    }

    /// 探测范围收敛：优先「本用户 + 有项目归属 + 端口 < 10000」，避免把系统守护进程全探一遍。
    private func probeTargets(from ports: [ListeningPort], limit: Int) -> [ListeningPort] {
        let owned = ports.filter { $0.isOwnedByCurrentUser && !$0.isNoise }
        let candidates = owned
            .filter { $0.project != nil || $0.port < 10000 }
            .sorted { lhs, rhs in
                if (lhs.project != nil) != (rhs.project != nil) { return lhs.project != nil }
                return lhs.port < rhs.port
            }
        return Array(candidates.prefix(limit))
    }
}