import Foundation
import Darwin

// MARK: - 传输层协议

public enum TransportProtocol: String, Sendable, Codable, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
}

// MARK: - 项目类型

public enum ProjectKind: String, Sendable, Codable {
    case node
    case python
    case java
    case go
    case rust
    case docker
    case git
    case other
}

// MARK: - 端口来源

/// 一个监听端口「为谁而开」。用于默认过滤掉 GUI 应用/系统守护进程的噪音端口。
public enum PortSource: String, Sendable, Codable {
    /// 能定位到具体代码项目（最有价值）
    case project
    /// Homebrew 管理的服务（postgres / redis / mysql ...）
    case brew
    /// .app 包内的进程（QQMusic、VS Code Helper 等，属于噪音）
    case app
    /// 系统组件（rapportd、ControlCenter、mDNSResponder 等，属于噪音）
    case system
    /// 其他（裸脚本、临时服务）
    case other
    /// 高位端口（49152+）且无法归属，通常是后台应用的临时端口
    case ephemeral

    public var isNoise: Bool { self == .app || self == .system || self == .ephemeral }

    public var label: String {
        switch self {
        case .project: return L("项目", "project")
        case .brew: return "brew"
        case .app: return L("应用", "app")
        case .system: return L("系统", "system")
        case .other: return L("其他", "other")
        case .ephemeral: return L("临时", "ephemeral")
        }
    }
}

// MARK: - 可达性

public enum Reachability: String, Sendable, Codable {
    /// TCP 可以握手成功
    case reachable
    /// 端口在 LISTEN，但连不上
    case unreachable
    /// 未探测
    case unknown

    public var symbol: String {
        switch self {
        case .reachable: return "●"
        case .unreachable: return "○"
        case .unknown: return "·"
        }
    }

    public var label: String {
        switch self {
        case .reachable: return L("可达", "reachable")
        case .unreachable: return L("无响应", "no response")
        case .unknown: return L("未探测", "not probed")
        }
    }
}

// MARK: - 项目引用

public struct ProjectRef: Sendable, Codable, Hashable {
    public let root: String
    public let name: String
    public let kind: ProjectKind

    public init(root: String, name: String, kind: ProjectKind) {
        self.root = root
        self.name = name
        self.kind = kind
    }
}

// MARK: - 采集原始态

public struct RawBinding: Sendable, Hashable {
    public let pid: Int32
    public let command: String
    public let uid: UInt32
    public let proto: TransportProtocol
    public let address: String
    public let port: Int

    public init(pid: Int32, command: String, uid: UInt32, proto: TransportProtocol, address: String, port: Int) {
        self.pid = pid
        self.command = command
        self.uid = uid
        self.proto = proto
        self.address = address
        self.port = port
    }
}

// MARK: - 进程状态

public struct ProcessStat: Sendable, Codable, Hashable {
    public let pid: Int32
    public let ppid: Int32
    public let cpuPercent: Double
    public let rssKB: Int
    public let elapsed: String
    /// 可执行文件完整路径（ps -o comm=），用于判断端口来源
    public let executable: String

    public init(pid: Int32, ppid: Int32, cpuPercent: Double, rssKB: Int, elapsed: String, executable: String = "") {
        self.pid = pid
        self.ppid = ppid
        self.cpuPercent = cpuPercent
        self.rssKB = rssKB
        self.elapsed = elapsed
        self.executable = executable
    }
}

// MARK: - 展示态：一个监听端口

public struct ListeningPort: Identifiable, Sendable, Codable, Hashable {
    public let pid: Int32
    public let command: String
    public let uid: UInt32
    public let proto: TransportProtocol
    public let address: String
    public let port: Int

    public var cwd: String?
    public var project: ProjectRef?
    public var cpuPercent: Double?
    public var rssKB: Int?
    public var elapsed: String?
    public var executable: String?
    public var reachability: Reachability

    public var id: String { "\(proto.rawValue)-\(pid)-\(port)" }

    public init(
        raw: RawBinding,
        cwd: String? = nil,
        project: ProjectRef? = nil,
        stat: ProcessStat? = nil,
        reachability: Reachability = .unknown
    ) {
        self.pid = raw.pid
        self.command = raw.command
        self.uid = raw.uid
        self.proto = raw.proto
        self.address = raw.address
        self.port = raw.port
        self.cwd = cwd
        self.project = project
        self.cpuPercent = stat?.cpuPercent
        self.rssKB = stat?.rssKB
        self.elapsed = stat?.elapsed
        self.executable = stat?.executable
        self.reachability = reachability
    }

    /// 端口来源分类。
    /// 顺序很关键：先认「用户级 .app」，再看项目归属，最后才入系统/噪音桶。
    public var source: PortSource {
        let path = executable ?? ""
        let home = NSHomeDirectory()

        // 1. 能定位到代码项目 → 最有价值的一类
        //    必须排在 .app 判定前：Xcode 自带的 python3 实际是 Python.app/Contents/MacOS/Python
        if project != nil { return .project }

        // 2. GUI 应用（包括 app 内部 helper、framework 内嵌 app）
        if path.contains(".app/Contents/") { return .app }

        // 3. 系统组件
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/") || path.hasPrefix("/usr/libexec/")
            || path.hasPrefix("/usr/lib/") || path.hasPrefix("/usr/sbin/") || path.hasPrefix("/sbin/") {
            return .system
        }

        // 4. 家目录下的隐藏目录（~/.lingma、~/.cursor ...）是工具的后台进程
        if path.hasPrefix(home + "/.") { return .app }

        // 5. 包管理器安装的服务
        if path.hasPrefix("/opt/homebrew") || path.hasPrefix("/usr/local/opt") || path.hasPrefix("/usr/local/Cellar") {
            return .brew
        }

        // 6. 高位端口（IANA 动态/私有区间）基本是后台应用的临时监听
        if port >= 49152 { return .ephemeral }
        return .other
    }

    /// GUI 应用/系统守护进程开的端口，默认不打扰用户
    public var isNoise: Bool { source.isNoise }

    /// 该端口所属进程是否属于当前用户（决定能否结束）
    public var isOwnedByCurrentUser: Bool { uid == getuid() }

    /// 用于本地访问的主机名
    public var localHost: String {
        switch address {
        case "*", "0.0.0.0", "127.0.0.1": return "127.0.0.1"
        case "::", "::1", "localhost": return "::1"
        default: return address
        }
    }

    /// 可直接点击打开的地址
    public var connectURL: URL? {
        let host = localHost
        let formatted = host.contains(":") ? "[\(host)]" : host
        return URL(string: "http://\(formatted):\(port)/")
    }

    public var displayName: String { project?.name ?? command }
}

// MARK: - 告警

public enum Severity: Int, Sendable, Codable, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .info: return L("提示", "info")
        case .warning: return L("注意", "warning")
        case .critical: return L("严重", "critical")
        }
    }
}

public enum IssueKind: String, Sendable, Codable {
    /// 同一端口被多个进程监听
    case duplicatePort
    /// 端口在监听但 TCP 连不上
    case unreachable
    /// 持有端口的进程 CPU 过高
    case highCPU
}

public struct Issue: Identifiable, Sendable, Codable, Hashable {
    public let kind: IssueKind
    public let severity: Severity
    /// 告警主体（端口号 / 进程名）
    public let subject: String
    public let message: String
    public let portIDs: [String]

    public var id: String { "\(kind.rawValue)-\(subject)" }

    public init(kind: IssueKind, severity: Severity, subject: String, message: String, portIDs: [String]) {
        self.kind = kind
        self.severity = severity
        self.subject = subject
        self.message = message
        self.portIDs = portIDs
    }
}

// MARK: - 系统状态

public struct SystemStatus: Sendable, Codable, Hashable {
    public let load1: Double
    public let load5: Double
    public let load15: Double
    public let uptimeSeconds: Double
    public let bootTime: Date?
    public let diskFreeBytes: Int64
    public let diskTotalBytes: Int64
    public let physicalMemoryBytes: UInt64
    public let cpuCount: Int

    public init(
        load1: Double,
        load5: Double,
        load15: Double,
        uptimeSeconds: Double,
        bootTime: Date?,
        diskFreeBytes: Int64,
        diskTotalBytes: Int64,
        physicalMemoryBytes: UInt64,
        cpuCount: Int
    ) {
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.uptimeSeconds = uptimeSeconds
        self.bootTime = bootTime
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.physicalMemoryBytes = physicalMemoryBytes
        self.cpuCount = cpuCount
    }
}

// MARK: - 一帧快照

public struct Snapshot: Sendable, Codable {
    public let generatedAt: Date
    public let durationMs: Int
    public let ports: [ListeningPort]
    public let issues: [Issue]
    public let system: SystemStatus

    public init(generatedAt: Date, durationMs: Int, ports: [ListeningPort], issues: [Issue], system: SystemStatus) {
        self.generatedAt = generatedAt
        self.durationMs = durationMs
        self.ports = ports
        self.issues = issues
        self.system = system
    }

    /// 按项目分组（无归属的归到 nil 组）
    public var portsByProject: [(project: ProjectRef?, ports: [ListeningPort])] {
        var buckets: [String: (ProjectRef?, [ListeningPort])] = [:]
        for port in ports {
            let key = port.project?.root ?? "\u{0}ungrouped"
            var bucket = buckets[key] ?? (port.project, [])
            bucket.1.append(port)
            buckets[key] = bucket
        }
        return buckets.values
            .map { (project: $0.0, ports: $0.1.sorted { $0.port < $1.port }) }
            .sorted { lhs, rhs in
                switch (lhs.project, rhs.project) {
                case let (l?, r?): return l.name < r.name
                case (nil, _?): return false
                case (_?, nil): return true
                default: return false
                }
            }
    }
}