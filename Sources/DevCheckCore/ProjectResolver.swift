import Foundation

/// 从进程 cwd 反向推断「这属于哪个项目」。
///
/// 规则：cwd 逐级向上，最多 8 层，命中第一个 marker 即为项目根。
/// 优先级：具体语言 marker > `.git` > 放弃（返回 nil）。
public final class ProjectResolver: @unchecked Sendable {
    private struct Marker {
        let file: String
        let kind: ProjectKind
    }

    /// 顺序即优先级
    private static let markers: [Marker] = [
        Marker(file: "package.json", kind: .node),
        Marker(file: "pom.xml", kind: .java),
        Marker(file: "build.gradle", kind: .java),
        Marker(file: "build.gradle.kts", kind: .java),
        Marker(file: "go.mod", kind: .go),
        Marker(file: "Cargo.toml", kind: .rust),
        Marker(file: "pyproject.toml", kind: .python),
        Marker(file: "requirements.txt", kind: .python),
        Marker(file: "Pipfile", kind: .python),
        Marker(file: "docker-compose.yml", kind: .docker),
        Marker(file: "compose.yaml", kind: .docker),
    ]

    private let maxDepth: Int
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var cache: [String: ProjectRef?] = [:]

    public init(maxDepth: Int = 8) {
        self.maxDepth = maxDepth
    }

    public func resolve(cwd: String) -> ProjectRef? {
        lock.lock()
        if let cached = cache[cwd] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolveUncached(cwd: cwd)

        lock.lock()
        cache[cwd] = resolved
        lock.unlock()
        return resolved
    }

    public func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private func resolveUncached(cwd: String) -> ProjectRef? {
        var url = URL(fileURLWithPath: cwd).standardizedFileURL

        for _ in 0..<maxDepth {
            // 先拦住「不是用户代码」的目录，避免 Xcode/VS Code/家目录工具目录被当成项目
            if Self.isNonProjectRoot(url) { break }

            if let marker = Self.markers.first(where: {
                fileManager.fileExists(atPath: url.appendingPathComponent($0.file).path)
            }) {
                return ProjectRef(
                    root: url.path,
                    name: projectName(at: url, kind: marker.kind),
                    kind: marker.kind
                )
            }

            // 碰到共享根就停，否则包管理器/IDE 自己的 .git 会被误认为用户项目
            let gitPath = url.appendingPathComponent(".git").path
            if fileManager.fileExists(atPath: gitPath) {
                return ProjectRef(root: url.path, name: url.lastPathComponent, kind: .git)
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    /// 包管理器 / 系统目录 / 家目录，不能当作项目根
    static func isSharedRoot(_ url: URL) -> Bool {
        let path = url.path
        let fixed: Set<String> = [
            "/", "/opt", "/opt/homebrew", "/usr", "/usr/local", "/usr/local/Cellar",
            "/tmp", "/private/tmp", "/private/var", "/var", "/Applications",
            "/Library", "/System", "/Volumes", "/Users",
        ]
        if fixed.contains(path) { return true }

        // /Users/<name>
        let components = url.pathComponents
        if components.count == 3, components[1] == "Users" { return true }
        return false
    }

    /// 工具/系统目录不是用户代码（即使里面有 package.json 或 .git）
    static func isNonProjectRoot(_ url: URL) -> Bool {
        if isSharedRoot(url) { return true }
        let path = url.path
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/Library") || path.hasPrefix(home + "/.") { return true }
        if path.hasPrefix("/Applications") || path.hasPrefix("/System") || path.hasPrefix("/Library") { return true }
        return false
    }

    private func projectName(at url: URL, kind: ProjectKind) -> String {
        if kind == .node,
           let data = try? Data(contentsOf: url.appendingPathComponent("package.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["name"] as? String,
           !name.isEmpty {
            return name
        }
        return url.lastPathComponent
    }
}