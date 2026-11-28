import XCTest
@testable import DevCheckCore

final class PortExplainerTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        L10n.shared.setLanguage(.zh)
    }

    private func holder(
        _ port: Int,
        pid: Int32,
        command: String,
        executable: String,
        reachability: Reachability = .unknown
    ) -> ListeningPort {
        ListeningPort(
            raw: RawBinding(pid: pid, command: command, uid: getuid(), proto: .tcp, address: "*", port: port),
            stat: ProcessStat(pid: pid, ppid: 1, cpuPercent: 0, rssKB: 1, elapsed: "1:00", executable: executable),
            reachability: reachability
        )
    }

    func testAirPlayOn5000IsExplained() {
        let ports = [holder(5000, pid: 804, command: "ControlCenter",
                            executable: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter")]
        let explanation = PortExplainer.explain(port: 5000, ports: ports)

        XCTAssertEqual(explanation.holders.count, 1)
        XCTAssertTrue(explanation.notes.contains { $0.contains("隔空播放") })
        XCTAssertTrue(explanation.suggestions.contains { $0.contains("隔空播放接收器") })
        XCTAssertTrue(explanation.suggestions.contains { $0.contains("5001") })
    }

    func testDuplicateListenersGetKillSuggestion() {
        let ports = [
            holder(9000, pid: 11, command: "node", executable: "/opt/homebrew/bin/node"),
            holder(9000, pid: 12, command: "node", executable: "/opt/homebrew/bin/node"),
        ]
        let explanation = PortExplainer.explain(port: 9000, ports: ports)
        XCTAssertTrue(explanation.notes.contains { $0.contains("2 个进程") })
        XCTAssertTrue(explanation.suggestions.contains { $0.contains("kill -TERM 11") })
    }

    func testUnreachableListenerIsCalledFakeAlive() {
        let ports = [holder(8080, pid: 21, command: "java", executable: "/usr/bin/java", reachability: .unreachable)]
        let explanation = PortExplainer.explain(port: 8080, ports: ports)
        XCTAssertTrue(explanation.notes.contains { $0.contains("假活") })
        XCTAssertTrue(explanation.suggestions.contains { $0.contains("kill -TERM 21") })
    }

    func testFreePortExplainsCommonUsage() {
        let explanation = PortExplainer.explain(port: 5173, ports: [])
        XCTAssertTrue(explanation.holders.isEmpty)
        XCTAssertTrue(explanation.notes.contains { $0.contains("Vite") })
        XCTAssertTrue(explanation.suggestions.contains { $0.contains("没有进程") })
    }

    func testEnglishOutput() {
        L10n.shared.setLanguage(.en)
        defer { L10n.shared.setLanguage(.zh) }

        let ports = [holder(5000, pid: 804, command: "ControlCenter",
                            executable: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter")]
        let explanation = PortExplainer.explain(port: 5000, ports: ports)
        XCTAssertTrue(explanation.notes.contains { $0.contains("AirPlay") })
        XCTAssertTrue(explanation.suggestions.contains { $0.contains("System Settings") })
    }

func testDockerProxyIsExplained() {
        let ports = [holder(5432, pid: 31, command: "docker-proxy",
                            executable: "/Applications/Docker.app/Contents/MacOS/com.docker.backend")]
        let explanation = PortExplainer.explain(port: 5432, ports: ports)
        XCTAssertTrue(explanation.notes.contains { $0.contains("docker-proxy") })
    }

    func testOllamaOn11434IsExplained() {
        let ports = [holder(11434, pid: 41, command: "ollama",
                            executable: "/Applications/Ollama.app/Contents/MacOS/Ollama")]
        let explanation = PortExplainer.explain(port: 11434, ports: ports)
        XCTAssertTrue(explanation.notes.contains { $0.contains("Ollama") })
        XCTAssertTrue(explanation.suggestions.contains { $0.contains("Ollama") })
    }

    func testBunIsExplained() {
        let ports = [holder(3000, pid: 51, command: "bun", executable: "/opt/homebrew/bin/bun")]
        let explanation = PortExplainer.explain(port: 3000, ports: ports)
        XCTAssertTrue(explanation.notes.contains { $0.contains("Bun") })
    }

    func testDenoIsExplained() {
        let ports = [holder(3000, pid: 52, command: "deno", executable: "/opt/homebrew/bin/deno")]
        let explanation = PortExplainer.explain(port: 3000, ports: ports)
        XCTAssertTrue(explanation.notes.contains { $0.contains("Deno") })
    }
}

