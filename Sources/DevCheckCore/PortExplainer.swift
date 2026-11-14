import Foundation

/// 单个端口的「人话解释」。
/// 这是产品最有价值的一层：把 `lsof` 的三行噪音翻译成「这是 AirPlay，去系统设置里关掉」。
public struct PortExplanation: Sendable, Codable {
    public let port: Int
    public let holders: [ListeningPort]
    /// 已知服务的背景解释（AirPlay、mDNS、数据库…）
    public let notes: [String]
    /// 下一步建议
    public let suggestions: [String]

    public init(port: Int, holders: [ListeningPort], notes: [String], suggestions: [String]) {
        self.port = port
        self.holders = holders
        self.notes = notes
        self.suggestions = suggestions
    }

    public var isEmpty: Bool { holders.isEmpty }
}

public enum PortExplainer {
    private struct KnownPort {
        let commands: [String]
        let note: (zh: String, en: String)
        let hint: (zh: String, en: String)
    }

    /// 系统服务占用的「众所周知的端口」→ 背景解释
    private static let knownSystemPorts: [Int: KnownPort] = [
        5000: KnownPort(
            commands: ["ControlCenter"],
            note: (
                "5000 是 macOS「隔空播放接收器（AirPlay Receiver）」的默认端口，由 ControlCenter 常驻监听。",
                "Port 5000 is macOS AirPlay Receiver, served by ControlCenter."
            ),
            hint: (
                "系统设置 → 通用 → 隔空投送与接力 → 关闭「隔空播放接收器」，或把你的服务换到 5001/5173。",
                "Turn it off in System Settings → General → AirDrop & Handoff → AirPlay Receiver, or move your service to 5001/5173."
            )
        ),
        7000: KnownPort(
            commands: ["ControlCenter"],
            note: (
                "7000 同属 AirPlay Receiver，和 5000 成对出现。",
                "7000 belongs to AirPlay Receiver too — it always comes with 5000."
            ),
            hint: (
                "同上：关掉「隔空播放接收器」，或换个端口。",
                "Same fix: disable AirPlay Receiver, or pick another port."
            )
        ),
        5353: KnownPort(
            commands: ["mDNSResponder"],
            note: (
                "5353 是 mDNS/Bonjour 的保留端口，被系统守护进程占用是正常的。",
                "5353 is reserved for mDNS/Bonjour; the system daemon holding it is normal."
            ),
            hint: (
                "不要动它。",
                "Leave it alone."
            )
        ),
        22: KnownPort(
            commands: ["sshd"],
            note: (
                "22 是「远程登录（SSH）」端口。",
                "Port 22 is SSH (Remote Login)."
            ),
hint: (
                "如果你没主动开 SSH，去 系统设置 → 通用 → 共享 检查。",
                "If you did not enable SSH, check System Settings → General → Sharing."
            )
        ),
        11434: KnownPort(
            commands: ["ollama"],
            note: (
                "11434 是 Ollama 大模型服务的默认端口，通常由后台常驻进程占用。",
                "Port 11434 is Ollama LLM service default, usually held by a background daemon."
            ),
            hint: (
                "不需要时可在 Ollama 设置里关闭，或把服务换到别的端口。",
                "Turn it off in Ollama settings if not needed, or move your service to another port."
            )
        ),
    ]

    /// 命令名 → 服务说明
    private static let knownCommands: [String: (zh: String, en: String)] = [
        "postgres": ("PostgreSQL 数据库", "PostgreSQL database"),
        "redis-server": ("Redis 缓存服务", "Redis cache server"),
        "mysqld": ("MySQL 数据库", "MySQL database"),
        "mongod": ("MongoDB 数据库", "MongoDB database"),
        "nginx": ("Nginx 反向代理", "Nginx reverse proxy"),
        "node": ("Node.js 进程", "Node.js process"),
        "Python": ("Python 进程", "Python process"),
        "java": ("Java 进程", "Java process"),
        "docker-proxy": (
            "Docker 容器的端口映射（真实进程在容器里，结束它不会停止容器）",
            "Docker port mapping — the real process lives inside the container; killing this does not stop it"
        ),
"rapportd": ("Handoff / 接力 相关守护进程", "Handoff / Continuity daemon"),
        "bun": ("Bun 运行时", "Bun runtime"),
        "deno": ("Deno 运行时", "Deno runtime"),
        "ollama": ("Ollama 大模型服务", "Ollama LLM service"),
        "gunicorn": ("Gunicorn Python WSGI 服务器", "Gunicorn Python WSGI server"),
        "uvicorn": ("Uvicorn Python ASGI 服务器", "Uvicorn Python ASGI server"),
        "php-fpm": ("PHP-FPM 进程", "PHP-FPM process"),
    ]

    /// 常见开发端口 → 说明
    private static let knownDevPorts: [Int: (zh: String, en: String)] = [
        3000: ("React / Next.js / CRA 默认端口", "React / Next.js / CRA default"),
        3001: ("常见的第二个前端服务", "Common second frontend server"),
        4000: ("Gatsby / 部分 Node 服务默认端口", "Gatsby / some Node servers"),
        4200: ("Angular CLI 默认端口", "Angular CLI default"),
        4321: ("Astro 默认端口", "Astro default"),
        5001: ("常见备用端口（避开 AirPlay 的 5000）", "Common fallback for AirPlay's 5000"),
        5173: ("Vite 默认端口", "Vite default"),
        5174: ("Vite 第二个实例（5173 被占用时会自动 +1）", "Second Vite instance (auto +1 when 5173 is taken)"),
        8000: ("Django / Python http.server 默认端口", "Django / Python http.server default"),
        8080: ("通用 HTTP 代理 / Tomcat 默认端口", "Generic HTTP proxy / Tomcat default"),
9000: ("PHP-FPM / SonarQube 等", "PHP-FPM / SonarQube and friends"),
        9200: ("Elasticsearch 默认端口", "Elasticsearch default"),
        11434: ("Ollama 默认端口", "Ollama default"),
        4873: ("Verdaccio 默认端口", "Verdaccio default"),
        27017: ("MongoDB 默认端口", "MongoDB default"),
        9092: ("Kafka / JMX 默认端口", "Kafka / JMX default"),
    ]

    public static func explain(port: Int, ports: [ListeningPort]) -> PortExplanation {
        let holders = ports.filter { $0.port == port && $0.proto == .tcp }
            .sorted { $0.pid < $1.pid }

        var notes: [String] = []
        var suggestions: [String] = []

        if let dev = knownDevPorts[port] {
            notes.append(L("\(port) 常见用途：\(dev.zh)。", "\(port) is usually \(dev.en)."))
        }

        let commands = Set(holders.map(\.command))

        if let known = knownSystemPorts[port],
           commands.contains(where: { known.commands.contains($0) }) {
            notes.append(L(known.note.zh, known.note.en))
            suggestions.append(L(known.hint.zh, known.hint.en))
        }

        for command in commands.sorted() {
            if let description = knownCommands[command] {
                notes.append(L("\(command) → \(description.zh)", "\(command) → \(description.en)"))
            }
        }

        if holders.isEmpty {
            suggestions.append(
                L("当前没有进程在监听 \(port)；如果你的服务起不来，看它日志里的实际错误（可能是 EADDRINUSE 之外的失败）。",
                  "Nothing is listening on \(port). If your server still fails, check its log — the error may not be EADDRINUSE at all.")
            )
            return PortExplanation(port: port, holders: [], notes: notes, suggestions: suggestions)
        }

        let pids = Set(holders.map(\.pid))
        if pids.count > 1 {
            let killList = holders.map { "kill -TERM \($0.pid)" }.joined(separator: " && ")
            notes.append(
                L("有 \(pids.count) 个进程同时监听 \(port)：通常是旧进程没退干净，或用了 SO_REUSEPORT。",
                  "\(pids.count) processes listen on \(port) at once — usually a stale process that never exited, or SO_REUSEPORT.")
            )
            suggestions.append(L("先终止重复的那几个：\(killList)", "Terminate the duplicates first: \(killList)"))
        }

        if let stuck = holders.first(where: { $0.reachability == .unreachable }) {
            notes.append(
                L("PID \(stuck.pid) 在监听但 TCP 握手失败，属于「假活」进程。",
                  "PID \(stuck.pid) is listening but the TCP handshake fails — it is fake-alive.")
            )
            suggestions.append(
                L("直接结束它：kill -TERM \(stuck.pid)（无效则 kill -9 \(stuck.pid)）",
                  "Kill it: kill -TERM \(stuck.pid) (then kill -9 \(stuck.pid) if needed)")
            )
        }

        let foreign = holders.filter { !$0.isOwnedByCurrentUser }
        if !foreign.isEmpty {
            let owners = Set(foreign.map(\.uid)).sorted().map(String.init).joined(separator: ", ")
            suggestions.append(
                L("其中部分进程属于其他用户（uid \(owners)），结束需要 sudo。",
                  "Some holders belong to other users (uid \(owners)); killing them needs sudo.")
            )
        }

        if holders.allSatisfy({ $0.isNoise }) {
            suggestions.append(
                L("这些是系统/应用进程，最省事的做法是换一个端口（例如 \(nextFreeCandidate(after: port))）。",
                  "These are system/app processes — the cheapest fix is a different port (e.g. \(nextFreeCandidate(after: port))).")
            )
        }

        return PortExplanation(port: port, holders: holders, notes: notes, suggestions: suggestions)
    }

    /// 给出一个建议端口（避开常见冲突区）
    static func nextFreeCandidate(after port: Int) -> Int {
        if port == 5000 || port == 7000 { return 5001 }
        if port < 1024 { return 8080 }
        return port + 1
    }
}
