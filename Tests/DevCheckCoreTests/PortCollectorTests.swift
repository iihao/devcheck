import XCTest
@testable import DevCheckCore

final class PortCollectorTests: XCTestCase {
    private let sample = """
    p705
    crapportd
    u501
    f11
    PTCP
    n*:49153
    f12
    PTCP
    n[::1]:49153
    p1234
    cnode
    u501
    f25
    PTCP
    n127.0.0.1:3000
    f26
    PTCP
    n*:5173
    """

    func testParseBindings() {
        let bindings = PortCollector.parseBindings(sample, proto: .tcp)
        XCTAssertEqual(bindings.count, 4)

        let node = bindings.filter { $0.pid == 1234 }
        XCTAssertEqual(node.count, 2)
        XCTAssertEqual(node.map(\.command).first, "node")
        XCTAssertEqual(node.map(\.uid).first, 501)
        XCTAssertEqual(Set(node.map(\.port)), [3000, 5173])
    }

    func testDedupeKeepsWildcard() {
        let bindings = PortCollector.parseBindings(sample, proto: .tcp)
        let deduped = PortCollector.dedupe(bindings)
        XCTAssertEqual(deduped.count, 3)

        let rapport = deduped.first { $0.pid == 705 }
        XCTAssertEqual(rapport?.address, "*", "通配地址应优先于 [::1] 保留")
    }

    func testParseNameVariants() {
        XCTAssertEqual(PortCollector.parseName("*:49153")?.address, "*")
        XCTAssertEqual(PortCollector.parseName("*:49153")?.port, 49153)
        XCTAssertEqual(PortCollector.parseName("127.0.0.1:3000")?.port, 3000)
        XCTAssertEqual(PortCollector.parseName("[::1]:8080")?.address, "::1")
        XCTAssertEqual(PortCollector.parseName("[::1]:8080")?.port, 8080)
        XCTAssertNil(PortCollector.parseName("*:*"))
        XCTAssertNil(PortCollector.parseName("no-port"))
        XCTAssertNil(PortCollector.parseName("*:99999"))
    }

    func testCollectOnThisMachine() throws {
        // 真实环境冒烟测试：至少能跑通（可能返回空数组）
        let bindings = try PortCollector.collect(includeUDP: false)
        for binding in bindings {
            XCTAssertTrue((1...65535).contains(binding.port))
            XCTAssertFalse(binding.command.isEmpty)
        }
    }
}