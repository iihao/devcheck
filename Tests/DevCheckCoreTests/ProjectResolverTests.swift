import XCTest
@testable import DevCheckCore

final class ProjectResolverTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("devcheck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = sandbox.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testResolveNodeProjectFromNestedCwd() throws {
        let root = try makeDirectory("demo-app")
        try #"{"name": "demo-app-pkg"}"#.write(
            to: root.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        let nested = try makeDirectory("demo-app/src/deep")

        let resolver = ProjectResolver()
        let project = resolver.resolve(cwd: nested.path)

        XCTAssertEqual(project?.kind, .node)
        XCTAssertEqual(project?.name, "demo-app-pkg")
        XCTAssertEqual(project?.root, root.path)
    }

    func testResolveGitRepoFallback() throws {
        let root = try makeDirectory("my-repo")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        let nested = try makeDirectory("my-repo/build/out")

        let project = ProjectResolver().resolve(cwd: nested.path)
        XCTAssertEqual(project?.kind, .git)
        XCTAssertEqual(project?.name, "my-repo")
    }

    func testResolveReturnsNilOutsideProject() throws {
        let plain = try makeDirectory("plain/dir")
        XCTAssertNil(ProjectResolver().resolve(cwd: plain.path))
    }

    func testCacheIsStable() throws {
        let root = try makeDirectory("cached")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        let resolver = ProjectResolver()
        let first = resolver.resolve(cwd: root.path)
        let second = resolver.resolve(cwd: root.path)
        XCTAssertEqual(first, second)
    }
}

final class RuleEngineTests: XCTestCase {
    private func port(port: Int, pid: Int32, command: String, reachability: Reachability = .reachable, cpu: Double = 0) -> ListeningPort {
        ListeningPort(
            raw: RawBinding(pid: pid, command: command, uid: getuid(), proto: .tcp, address: "*", port: port),
            stat: ProcessStat(pid: pid, ppid: 1, cpuPercent: cpu, rssKB: 1024, elapsed: "01:00"),
            reachability: reachability
        )
    }

    func testDuplicatePortDetected() {
        let ports = [port(port: 3000, pid: 1, command: "node"), port(port: 3000, pid: 2, command: "node")]
        let issues = RuleEngine.evaluate(ports: ports)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .duplicatePort)
        XCTAssertEqual(issues.first?.subject, "3000")
    }

    func testUnreachableDetected() {
        let ports = [port(port: 8080, pid: 3, command: "java", reachability: .unreachable)]
        XCTAssertEqual(RuleEngine.evaluate(ports: ports).first?.kind, .unreachable)
    }

    func testHighCPUDetected() {
        let ports = [port(port: 5173, pid: 4, command: "vite", cpu: 95)]
        XCTAssertEqual(RuleEngine.evaluate(ports: ports).first?.kind, .highCPU)
    }

    func testHealthyPortsProduceNoIssue() {
        let ports = [port(port: 4000, pid: 5, command: "python3")]
        XCTAssertTrue(RuleEngine.evaluate(ports: ports).isEmpty)
    }
}

final class TCProbeTests: XCTestCase {
    func testHostsResolution() {
        XCTAssertEqual(TCProbe.hosts(for: "*"), ["127.0.0.1", "::1"])
        XCTAssertEqual(TCProbe.hosts(for: "::"), ["::1"])
        XCTAssertEqual(TCProbe.hosts(for: "10.0.0.2"), ["10.0.0.2"])
    }

    func testClosedPortIsUnreachable() {
        // 选一个大概率没人监听的高位端口
        XCTAssertFalse(TCProbe.reachable(address: "127.0.0.1", port: 59999, timeout: 0.2))
    }
}
final class PortSourceTests: XCTestCase {
    private func port(_ port: Int, executable: String, project: ProjectRef? = nil) -> ListeningPort {
        ListeningPort(
            raw: RawBinding(pid: 42, command: "demo", uid: getuid(), proto: .tcp, address: "*", port: port),
            project: project,
            stat: ProcessStat(pid: 42, ppid: 1, cpuPercent: 0, rssKB: 1024, elapsed: "01:00", executable: executable)
        )
    }

    func testAppBundleIsNoise() {
        let p = port(19443, executable: "/Applications/QQMusic.app/Contents/MacOS/QQMusic")
        XCTAssertEqual(p.source, .app)
        XCTAssertTrue(p.isNoise)
    }

    func testSystemDaemonIsNoise() {
        let p = port(49153, executable: "/usr/libexec/rapportd")
        XCTAssertEqual(p.source, .system)
        XCTAssertTrue(p.isNoise)
    }

    func testHomebrewPathIsBrew() {
        let p = port(6379, executable: "/opt/homebrew/opt/redis/bin/redis-server")
        XCTAssertEqual(p.source, .brew)
        XCTAssertFalse(p.isNoise)
    }

    func testHiddenHomeDirectoryIsApp() {
        let p = port(36510, executable: NSHomeDirectory() + "/.lingma/vscode/bin/Lingma")
        XCTAssertEqual(p.source, .app)
    }

    func testEphemeralUnknownProcessIsNoise() {
        let p = port(60001, executable: "/tmp/scratch/thing")
        XCTAssertEqual(p.source, .ephemeral)
        XCTAssertTrue(p.isNoise)
    }

    func testProjectWinsOverBrewBinary() {
        let project = ProjectRef(root: "/Users/x/user-portal", name: "user-portal", kind: .node)
        let p = port(3000, executable: "/opt/homebrew/bin/node", project: project)
        XCTAssertEqual(p.source, .project)
        XCTAssertFalse(p.isNoise)
    }

    func testSharedRootsAreNotProjects() {
        XCTAssertTrue(ProjectResolver.isSharedRoot(URL(fileURLWithPath: "/opt/homebrew")))
        XCTAssertTrue(ProjectResolver.isSharedRoot(URL(fileURLWithPath: "/Users/example")))
        XCTAssertTrue(ProjectResolver.isSharedRoot(URL(fileURLWithPath: "/tmp")))
        XCTAssertFalse(ProjectResolver.isSharedRoot(URL(fileURLWithPath: "/Users/example/Projects/devcheck")))
    }
}

final class PortSourceRegressionTests: XCTestCase {
    /// 回归：Xcode 自带 python3 的路径里带 Python.app，不应被当成 GUI 应用隐藏
    func testFrameworkEmbeddedAppIsNotNoise() {
        let project = ProjectRef(root: "/tmp/x/data-api", name: "data-api", kind: .python)
        let port = ListeningPort(
            raw: RawBinding(pid: 1, command: "Python", uid: getuid(), proto: .tcp, address: "*", port: 8000),
            project: project,
            stat: ProcessStat(
                pid: 1, ppid: 1, cpuPercent: 0, rssKB: 1024, elapsed: "01:00",
                executable: "/System/Library/Frameworks/Python.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
            )
        )
        XCTAssertEqual(port.source, .project)
        XCTAssertFalse(port.isNoise)
    }

    /// 回归：ControlCenter 这类系统 CoreServices 下的 .app 仍应是噪音
    func testCoreServicesAppIsNoise() {
        let port = ListeningPort(
            raw: RawBinding(pid: 1, command: "ControlCenter", uid: getuid(), proto: .tcp, address: "*", port: 5000),
            stat: ProcessStat(
                pid: 1, ppid: 1, cpuPercent: 0, rssKB: 1024, elapsed: "01:00",
                executable: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"
            )
        )
        XCTAssertEqual(port.source, .app)
        XCTAssertTrue(port.isNoise)
    }

    /// 回归：IDE / 家目录工具目录里的 package.json 不该被当成项目
    func testToolingDirectoriesAreNotProjects() {
        let resolver = ProjectResolver()
        XCTAssertNil(resolver.resolve(cwd: NSHomeDirectory() + "/.vscode/extensions/foo/bar"))
        XCTAssertNil(resolver.resolve(cwd: NSHomeDirectory() + "/Library/Application Support/SomeApp"))
    }
}
