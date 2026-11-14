import Foundation
import DevCheckCore
import AppKit

enum CLI {
    /// 同步入口（保证 NSApplication 在主线程启动）
    static func run(_ arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            runApp()
            return 0
        }

        switch command {
        case "app":
            runApp()
            return 0
        case "ports", "ls":
            return blocking { await runPorts(Array(arguments.dropFirst())) }
        case "doctor", "check":
            return blocking { await runDoctor(Array(arguments.dropFirst())) }
        case "menu", "preview":
            return blocking { await runMenuPreview() }
        case "why":
            return blocking { await runWhy(Array(arguments.dropFirst())) }
        case "--version", "-v", "version":
            print("devcheck \(DevCheckVersion.current)")
            return 0
        case "-h", "--help", "help":
            printUsage()
            return 0
        default:
            FileHandle.standardError.write(Data((L("未知命令：", "Unknown command: ") + "\(command)\n\n").utf8))
            printUsage()
            return 2
        }
    }

    /// 把异步采集收束回同步调用：CLI 用完即退，用信号量等待是安全的。
    private final class ExitCodeBox: @unchecked Sendable {
        var value: Int32 = 0
    }

    private static func blocking(_ work: @escaping () async -> Int32) -> Int32 {
        let box = ExitCodeBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            box.value = await work()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    // MARK: - 菜单栏

    static func runApp() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = StatusBarController()
        appControllers.append(controller)
        controller.start()
        app.run()
    }

    // MARK: - devcheck ports

    private static func runPorts(_ arguments: [String]) async -> Int32 {
        var options = SnapshotOptions()
        var asJSON = false
        var mineOnly = false
        var includeNoise = false

        for argument in arguments {
            switch argument {
            case "--json", "-j": asJSON = true
            case "--udp": options.includeUDP = true
            case "--no-probe": options.probe = false
            case "--mine": mineOnly = true
            case "--all": includeNoise = true
            default:
                FileHandle.standardError.write(Data((L("忽略未知参数：", "Ignoring unknown option: ") + "\(argument)\n").utf8))
            }
        }

        let snapshot = await SnapshotBuilder().build(options: options)
        var ports = snapshot.ports
        if !includeNoise { ports = ports.filter { !$0.isNoise } }
        if mineOnly {
            ports = ports.filter(\.isOwnedByCurrentUser)
        }

        if asJSON {
            printJSON(ports)
            return 0
        }

        let hidden = snapshot.ports.count - (includeNoise ? snapshot.ports.count : snapshot.ports.filter { !$0.isNoise }.count)
        let hiddenText = hidden > 0
            ? L("（已隐藏 \(hidden) 个应用/系统端口，--all 查看）",
                "(\(hidden) app/system ports hidden — use --all)")
            : ""
        print(L("\(ports.count) 个监听端口 · 告警 \(snapshot.issues.count) 条 · 采集 \(snapshot.durationMs)ms \(hiddenText)",
                "\(ports.count) listening ports · \(snapshot.issues.count) issues · collected in \(snapshot.durationMs)ms \(hiddenText)"))
        print("")

        let rows = ports.map { port -> [String] in
            [String(port.port),
             port.proto.rawValue,
             port.reachability.symbol,
             String(port.pid),
             String(format: "%.1f%%", port.cpuPercent ?? 0),
             port.source.label,
             port.project.map { "\($0.name)(\($0.kind.rawValue))" } ?? "-",
             port.command]
        }
        print(Format.table(header: [L("端口", "PORT"), L("协议", "PROTO"), L("状态", "STATE"), "PID", "CPU", L("来源", "SOURCE"), L("项目", "PROJECT"), L("命令", "COMMAND")], rows: rows))
        return 0
    }

    // MARK: - devcheck doctor

    private static func runDoctor(_ arguments: [String]) async -> Int32 {
        var options = SnapshotOptions()
        var includeNoise = false
        for argument in arguments {
            if argument == "--udp" { options.includeUDP = true }
            if argument == "--all" { includeNoise = true }
        }

        let snapshot = await SnapshotBuilder().build(options: options)
        let allOwned = snapshot.ports.filter(\.isOwnedByCurrentUser)
        let noise = allOwned.filter(\.isNoise)
        let owned = includeNoise ? allOwned : allOwned.filter { !$0.isNoise }
        let others = snapshot.ports.filter { !$0.isOwnedByCurrentUser }

        print(L("DevCheck 体检报告 · \(snapshot.generatedAt)", "DevCheck report · \(snapshot.generatedAt)"))
        print(L("监听端口 \(snapshot.ports.count) 个（我的 \(owned.count) / 其他用户 \(others.count)）· 采集耗时 \(snapshot.durationMs)ms",
                "\(snapshot.ports.count) listening ports (mine \(owned.count) / others \(others.count)) · collected in \(snapshot.durationMs)ms"))
        if !noise.isEmpty {
            print(L("已隐藏 \(noise.count) 个应用/系统端口", "\(noise.count) app/system ports hidden")
                  + (includeNoise ? "" : L("，用 --all 查看", " — use --all to show")))
        }
        print("")

        if snapshot.issues.isEmpty {
            print(L("[告警] 无", "[issues] none"))
        } else {
            print(L("[告警] \(snapshot.issues.count) 条", "[issues] \(snapshot.issues.count)"))
            for issue in snapshot.issues {
                print("  ⚠︎ \(issue.message)")
            }
        }
        print("")

        print(L("[我的服务]", "[my services]"))
        if owned.isEmpty {
            print(L("  （无）", "  (none)"))
        } else {
            for port in owned.sorted(by: { $0.port < $1.port }) {
                let project = port.project.map { "  ← \($0.name) (\($0.root))" } ?? ""
                let state = port.reachability.symbol
                let cpu = String(format: "%.1f%%", port.cpuPercent ?? 0)
                print("  \(state) \(port.port)\t\(port.command)\tPID \(port.pid)\tCPU \(cpu)\t[\(port.source.label)]\(project)")
            }
        }
        print("")

        if !others.isEmpty {
            print(L("[其他用户/系统]（\(others.count) 个，需 sudo 才能管理）",
                    "[other users / system] (\(others.count), sudo required to manage)"))
            let summary = others
                .sorted { $0.port < $1.port }
                .prefix(15)
                .map { "\($0.port)(\($0.command))" }
                .joined(separator: "  ")
            print("  \(summary)")
            print("")
        }

        let system = snapshot.system
        print(L("[系统]", "[system]"))
        print(L(String(format: "  负载 %.2f / %.2f / %.2f（\(system.cpuCount) 核）", system.load1, system.load5, system.load15),
                String(format: "  load %.2f / %.2f / %.2f (\(system.cpuCount) cores)", system.load1, system.load5, system.load15)))
        print(L("  磁盘 可用 \(Format.bytes(system.diskFreeBytes)) / 共 \(Format.bytes(system.diskTotalBytes))",
                "  disk \(Format.bytes(system.diskFreeBytes)) free / \(Format.bytes(system.diskTotalBytes))"))
        print(L("  内存 \(Format.memory(system.physicalMemoryBytes)) · 已运行 \(Format.duration(system.uptimeSeconds))",
                "  memory \(Format.memory(system.physicalMemoryBytes)) · up \(Format.duration(system.uptimeSeconds))"))
        return 0
    }

    // MARK: - devcheck menu（纯文本预览菜单栏内容）

    private static func runMenuPreview() async -> Int32 {
        let snapshot = await SnapshotBuilder().build()
        let visible = snapshot.ports.filter { !$0.isNoise }
        let noise = snapshot.ports.filter(\.isNoise)

        func line(_ text: String, depth: Int = 1) {
            print(String(repeating: "    ", count: depth) + text)
        }

        print(L("╭─ DevCheck  菜单栏内容预览", "╭─ DevCheck  menu bar preview"))
        line(L("\(snapshot.ports.count) 个监听端口 · 采集 \(snapshot.durationMs)ms · \(Format.time(snapshot.generatedAt))",
                 "\(snapshot.ports.count) ports · \(snapshot.durationMs)ms · \(Format.time(snapshot.generatedAt))"), depth: 1)
        print("│")

        if !snapshot.issues.isEmpty {
            line(L("告警 \(snapshot.issues.count) 条", "\(snapshot.issues.count) issue(s)"))
            for issue in snapshot.issues {
                line("⚠︎ \(issue.message)", depth: 2)
            }
            print("│")
        }

        let groups = Dictionary(grouping: visible) { $0.project?.root ?? "\u{0}" }
        for (key, ports) in groups.sorted(by: { lhs, rhs in
            (lhs.value.first?.project?.name ?? "~") < (rhs.value.first?.project?.name ?? "~")
        }) {
            let project = ports.first?.project
            let header = project.map { "\($0.name) · \($0.kind.rawValue)" } ?? (key == "\u{0}" ? L("未归类进程", "Unclassified") : key)
            line(header)
            for port in ports.sorted(by: { $0.port < $1.port }) {
                let cpu = String(format: "%.1f%%", port.cpuPercent ?? 0)
                line("\(port.reachability.symbol) \(port.port)  \(port.command)  PID \(port.pid)  [\(port.source.label) \(cpu)]", depth: 2)
                line(L("└ 在浏览器打开 / 复制地址 / 在 Finder 中显示 / 结束进程",
                         "└ open in browser / copy address / reveal in Finder / kill process"), depth: 3)
            }
            print("│")
        }

        if !noise.isEmpty {
            line(L("应用/系统端口（\(noise.count)）  ▸ 折叠子菜单", "App/system ports (\(noise.count))  ▸ collapsed submenu"), depth: 1)
            let sample = noise.sorted { $0.port < $1.port }.prefix(6)
                .map { "\($0.port) \($0.command)" }
                .joined(separator: L("、", ", "))
            line("\(sample) …", depth: 2)
            print("│")
        }

        let system = snapshot.system
        line(L("系统状态", "System"))
        line(L(String(format: "负载 %.2f / %.2f / %.2f", system.load1, system.load5, system.load15),
                              String(format: "load %.2f / %.2f / %.2f", system.load1, system.load5, system.load15)), depth: 2)
        line(L("磁盘 \(Format.bytes(system.diskFreeBytes)) 可用 / \(Format.bytes(system.diskTotalBytes))",
                              "disk \(Format.bytes(system.diskFreeBytes)) free / \(Format.bytes(system.diskTotalBytes))"), depth: 2)
        line(L("内存 \(Format.memory(system.physicalMemoryBytes)) · 已运行 \(Format.duration(system.uptimeSeconds))",
                              "memory \(Format.memory(system.physicalMemoryBytes)) · up \(Format.duration(system.uptimeSeconds))"), depth: 2)
        print("│")
        line(L("立即刷新       退出 DevCheck", "Refresh now       Quit DevCheck"))
        print("╰─")
        return 0
    }

    // MARK: - devcheck why <port>

    private static func runWhy(_ arguments: [String]) async -> Int32 {
        var asJSON = false
        var numericArgs: [String] = []
        for argument in arguments {
            if argument == "--json" || argument == "-j" { asJSON = true }
            else { numericArgs.append(argument) }
        }

        let numeric = numericArgs.compactMap { Int($0) }
        guard let port = numeric.first, (1...65535).contains(port) else {
            FileHandle.standardError.write(Data((L("用法：devcheck why <port> [--json]   例如 devcheck why 5000", "usage: devcheck why <port> [--json]   e.g. devcheck why 5000") + "\n").utf8))
            return 2
        }

        var options = SnapshotOptions()
        options.includeUDP = true
        var snapshot = await SnapshotBuilder().build(options: options)

        // 目标端口即使是被刻意隐藏的噪音端口，也要探一下（只探一个，代价可忽略）
        let targetPorts = snapshot.ports.filter { $0.port == port && $0.proto == .tcp }
        if !targetPorts.isEmpty {
            let reachability = await HealthChecker().probe(ports: targetPorts, timeout: 0.8)
            snapshot = Snapshot(
                generatedAt: snapshot.generatedAt,
                durationMs: snapshot.durationMs,
                ports: snapshot.ports.map { candidate in
                    guard let state = reachability[candidate.id] else { return candidate }
                    var copy = candidate
                    copy.reachability = state
                    return copy
                },
                issues: snapshot.issues,
                system: snapshot.system
            )
        }

        let explanation = PortExplainer.explain(port: port, ports: snapshot.ports)

        if asJSON {
            printWhyJSON(explanation)
            return 0
        }

        print(L("端口 \(port)：\(explanation.holders.count) 个进程占用",
                "Port \(port): \(explanation.holders.count) process(es) listening"))
        print("")

        for holder in explanation.holders {
            let owner = holder.isOwnedByCurrentUser ? L("我的", "mine") : "uid \(holder.uid)"
            print("  \(holder.reachability.symbol) \(holder.command)  PID \(holder.pid)  [\(holder.source.label)/\(owner)]  \(holder.reachability.label)")
            if let project = holder.project {
                print(L("      项目：\(project.name)（\(project.root)）", "      project: \(project.name) (\(project.root))"))
            } else if let cwd = holder.cwd {
                print(L("      目录：\(cwd)", "      cwd: \(cwd)"))
            }
            if let executable = holder.executable, !executable.isEmpty {
                print(L("      程序：\(executable)", "      binary: \(executable)"))
            }
        }

        if !explanation.notes.isEmpty {
            print("")
            for note in explanation.notes {
                print(L("  说明：", "  note: ") + note)
            }
        }

        if !explanation.suggestions.isEmpty {
            print("")
            for suggestion in explanation.suggestions {
                print(L("  建议：", "  fix: ") + suggestion)
            }
        }
        return 0
    }

    // MARK: - 辅助

    private static func printJSON(_ ports: [ListeningPort]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(ports), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func printWhyJSON(_ explanation: PortExplanation) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(explanation), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func printUsage() {
        print(L("""
        DevCheck · 工程机体检 + 端口地图

        用法:
          devcheck                 启动菜单栏（默认）
          devcheck why <port> [--json]   某个端口到底被谁占了、该怎么办
          devcheck ports [选项]     列出监听端口
          devcheck doctor          人类可读的体检报告
          devcheck menu            纯文本预览菜单栏内容
          devcheck --version       版本号
          devcheck help            显示帮助

        ports 选项:
          --json, -j     以 JSON 输出（便于脚本消费）
          --udp          包含 UDP 端口
          --mine         只看当前用户的端口
          --all          包含 GUI 应用/系统端口（默认隐藏）
          --no-probe     跳过 TCP 可达性探测（更快）
        """, """
        DevCheck · machine checkup + port map for macOS

        Usage:
          devcheck                 start the menu bar app (default)
          devcheck why <port> [--json]   who holds this port, and what to do about it
          devcheck ports [options] list listening ports
          devcheck doctor          human-readable health report
          devcheck menu            render the menu bar content as text
          devcheck --version       print version
          devcheck help            show this help

        ports options:
          --json, -j     machine-readable JSON
          --udp          include UDP sockets
          --mine         only the current user's ports
          --all          include GUI app / system ports (hidden by default)
          --no-probe     skip TCP reachability probing (faster)
        """))
    }
}

/// 全局持有，防止控制器被提前释放
var appControllers: [StatusBarController] = []
