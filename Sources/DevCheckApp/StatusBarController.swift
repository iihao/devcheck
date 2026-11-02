import AppKit
import DevCheckCore

enum Format {
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: value)
    }

    static func memory(_ value: UInt64) -> String {
        String(format: "%.0f GB", Double(value) / 1_073_741_824)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return L("\(days)天\(hours)小时", "\(days)d \(hours)h") }
        if hours > 0 { return L("\(hours)小时\(minutes)分", "\(hours)h \(minutes)m") }
        return L("\(minutes)分", "\(minutes)m")
    }

    static func pad(_ text: String, _ width: Int) -> String {
        let padding = max(0, width - text.count)
        return text + String(repeating: " ", count: padding)
    }

    static func table(header: [String], rows: [[String]]) -> String {
        var widths = header.map(\.count)
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        func render(_ cells: [String]) -> String {
            cells.enumerated()
                .map { index, cell in index == cells.count - 1 ? cell : pad(cell, widths[index]) }
                .joined(separator: "  ")
        }
        return ([render(header)] + rows.map(render)).joined(separator: "\n")
    }
}

/// 菜单栏控制器：图标 + 菜单，5 秒刷新一帧快照。
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let builder = SnapshotBuilder()
    private let options: SnapshotOptions
    private let menu = NSMenu()
    private var snapshot: Snapshot?
    private var timer: Timer?
    private var isRefreshing = false
    private var isMenuOpen = false

    final class PortBox: NSObject {
        let port: ListeningPort
        init(_ port: ListeningPort) { self.port = port }
    }

    init(options: SnapshotOptions = SnapshotOptions()) {
        self.options = options
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        menu.delegate = self
        statusItem.menu = menu
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, !self.isMenuOpen else { return }
            self.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // 调试/截图用：DEVCHECK_OPEN_MENU=1 启动后自动展开菜单
        if ProcessInfo.processInfo.environment["DEVCHECK_OPEN_MENU"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.statusItem.button?.performClick(nil)
            }
        }
    }

    // MARK: - 状态栏按钮

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "DevCheck") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }
        button.title = " …"
        button.toolTip = L("DevCheck · 工程机体检", "DevCheck · machine checkup")
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let owned = snapshot?.ports.filter { $0.isOwnedByCurrentUser && !$0.isNoise }.count ?? 0
        let warnings = snapshot?.issues.filter { $0.severity >= .warning }.count ?? 0
        button.title = warnings > 0 ? " \(owned) ⚠︎\(warnings)" : " \(owned)"
    }

    // MARK: - 采集

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let builder = self.builder
        let options = self.options
        Task.detached(priority: .utility) {
            let snapshot = await builder.build(options: options)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.snapshot = snapshot
                self.isRefreshing = false
                self.updateButton()
            }
        }
    }

    // MARK: - 菜单

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let snapshot else {
            menu.addItem(disabledItem(L("正在体检…", "Collecting…")))
            menu.addItem(.separator())
            addFooter(to: menu)
            return
        }

        let header = disabledItem(L("\(snapshot.ports.count) 个监听端口 · 采集 \(snapshot.durationMs)ms · \(Format.time(snapshot.generatedAt))",
                                    "\(snapshot.ports.count) ports · \(snapshot.durationMs)ms · \(Format.time(snapshot.generatedAt))"))
        menu.addItem(header)
        menu.addItem(.separator())

        addIssueSection(to: menu, snapshot: snapshot)
        addPortSections(to: menu, snapshot: snapshot)
        addSystemSection(to: menu, snapshot: snapshot)
        addFooter(to: menu)
    }

    private func addIssueSection(to menu: NSMenu, snapshot: Snapshot) {
        guard !snapshot.issues.isEmpty else { return }
        menu.addItem(disabledItem(L("告警 \(snapshot.issues.count) 条", "\(snapshot.issues.count) issue(s)")))
        for issue in snapshot.issues.prefix(6) {
            let item = NSMenuItem(title: "\(issue.severity == .warning ? "⚠︎" : "ℹ︎") \(issue.message)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    private func addPortSections(to menu: NSMenu, snapshot: Snapshot) {
        let visible = snapshot.ports.filter { !$0.isNoise }
        let noise = snapshot.ports.filter(\.isNoise)

        for group in groupedByProject(visible) {
            let title: String
            if let project = group.project {
                title = "\(project.name) · \(project.kind.rawValue)"
            } else {
                title = L("未归类进程", "Unclassified")
            }

            menu.addItem(disabledItem(title))
            for port in group.ports {
                menu.addItem(portMenuItem(for: port))
            }
            menu.addItem(.separator())
        }

        if !noise.isEmpty {
            let item = NSMenuItem(title: L("应用/系统端口（\(noise.count)）", "App/system ports (\(noise.count))"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for port in noise.sorted(by: { $0.port < $1.port }).prefix(25) {
                submenu.addItem(portMenuItem(for: port))
            }
            item.submenu = submenu
            menu.addItem(item)
            menu.addItem(.separator())
        }
    }

    /// 按项目分组，无项目的端口归到同一组
    private func groupedByProject(_ ports: [ListeningPort]) -> [(project: ProjectRef?, ports: [ListeningPort])] {
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

    private func addSystemSection(to menu: NSMenu, snapshot: Snapshot) {
        menu.addItem(disabledItem(L("系统状态", "System")))
        let system = snapshot.system
        let load = L(String(format: "负载 %.2f / %.2f / %.2f", system.load1, system.load5, system.load15),
                     String(format: "Load %.2f / %.2f / %.2f", system.load1, system.load5, system.load15))
        let disk = L("磁盘 \(Format.bytes(system.diskFreeBytes)) 可用 / \(Format.bytes(system.diskTotalBytes))",
                     "Disk \(Format.bytes(system.diskFreeBytes)) free / \(Format.bytes(system.diskTotalBytes))")
        let memory = L("内存 \(Format.memory(system.physicalMemoryBytes)) · 已运行 \(Format.duration(system.uptimeSeconds))",
                       "Memory \(Format.memory(system.physicalMemoryBytes)) · up \(Format.duration(system.uptimeSeconds))")
        for line in [load, disk, memory] {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.indentationLevel = 1
            menu.addItem(item)
        }
    }

    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(actionItem(L("立即刷新", "Refresh now"), #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(actionItem(L("退出 DevCheck", "Quit DevCheck"), #selector(quit), keyEquivalent: "q"))
    }

    private func portMenuItem(for port: ListeningPort) -> NSMenuItem {
        let title = "\(port.reachability.symbol) \(port.port)  \(port.command)  \(Format.pid(port.pid))"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = PortBox(port)

        let submenu = NSMenu()
        let info = port.project.map { "\($0.root)" } ?? (port.cwd ?? "未知路径")
        let infoItem = NSMenuItem(title: info, action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        submenu.addItem(infoItem)

        let state = NSMenuItem(title: L("状态：\(port.proto.rawValue) \(port.address) · \(port.reachability.label)",
                                       "State: \(port.proto.rawValue) \(port.address) · \(port.reachability.label)"), action: nil, keyEquivalent: "")
        state.isEnabled = false
        submenu.addItem(state)

        if let cpu = port.cpuPercent, let rss = port.rssKB {
            let usage = L(String(format: "CPU %.1f%% · 内存 %@ · 运行 %@", cpu, Format.bytes(Int64(rss) * 1024), port.elapsed ?? "-"),
                          String(format: "CPU %.1f%% · memory %@ · up %@", cpu, Format.bytes(Int64(rss) * 1024), port.elapsed ?? "-"))
            let usageItem = NSMenuItem(title: usage, action: nil, keyEquivalent: "")
            usageItem.isEnabled = false
            submenu.addItem(usageItem)
        }

        submenu.addItem(.separator())

        if let url = port.connectURL, port.proto == .tcp {
            submenu.addItem(actionItem(L("在浏览器打开 \(url.absoluteString)", "Open \(url.absoluteString)"), #selector(openPort(_:)), box: PortBox(port)))
        }
        submenu.addItem(actionItem(L("复制地址", "Copy address"), #selector(copyAddress(_:)), box: PortBox(port)))

        if port.cwd != nil {
            submenu.addItem(actionItem(L("在 Finder 中显示", "Reveal in Finder"), #selector(revealInFinder(_:)), box: PortBox(port)))
        }

        submenu.addItem(.separator())
        let kill = actionItem(L("结束进程 (\(port.pid))", "Kill process (\(port.pid))"), #selector(killPort(_:)), box: PortBox(port))
        kill.isEnabled = port.isOwnedByCurrentUser
        submenu.addItem(kill)

        item.submenu = submenu
        return item
    }

    // MARK: - 菜单构造小工具

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ selector: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func actionItem(_ title: String, _ selector: Selector, box: PortBox) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = box
        return item
    }

    // MARK: - 动作

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func openPort(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? PortBox, let url = box.port.connectURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyAddress(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? PortBox else { return }
        let text = box.port.connectURL?.absoluteString ?? "localhost:\(box.port.port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? PortBox else { return }
        let path = box.port.project?.root ?? box.port.cwd
        guard let path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func killPort(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? PortBox else { return }
        let port = box.port
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = L("结束进程 \(port.command)（PID \(port.pid)）？", "Kill \(port.command) (PID \(port.pid))?")
        alert.informativeText = L("该进程正占用端口 \(port.port)，未保存的工作可能丢失。将发送 SIGTERM 优雅退出。",
                                  "It holds port \(port.port). Unsaved work may be lost. Sends SIGTERM for a graceful exit.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("结束进程", "Kill"))
        alert.addButton(withTitle: L("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if kill(port.pid, SIGTERM) != 0 {
            let failure = NSAlert()
            failure.messageText = L("结束失败", "Kill failed")
            failure.informativeText = L("errno = \(errno)，可能需要 sudo 权限。", "errno = \(errno); sudo may be required.")
            failure.runModal()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension Format {
    static func pid(_ value: Int32) -> String { "PID \(value)" }
}