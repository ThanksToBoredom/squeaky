import XCTest
@testable import Squeaky

final class YaraTests: XCTestCase {
    func testCompilationAndScanBoundaries() throws {
        XCTAssertTrue(YaraRules.compile([]).isEmpty)
        XCTAssertTrue(YaraRules.compile([("bad", "not a rule")]).isEmpty)
        XCTAssertTrue(YaraRules.compile([("unsupported", "import \"missing\" rule x { condition: true }")]).isEmpty)
        let source = "rule probe { strings: $a = \"SQUEAKY-TEST\" condition: $a }"
        let rules = YaraRules.compile([("one", source), ("two", source)])
        XCTAssertEqual(rules.count, 2)
        let rule = try XCTUnwrap(rules.first)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(rule.scan(file: file).completed)
        try Data().write(to: file)
        XCTAssertTrue(rule.scan(file: file).names.isEmpty)
        try Data("SQUEAKY-TEST".utf8).write(to: file)
        XCTAssertEqual(rule.scan(file: file).names, ["probe"])
        XCTAssertTrue(rule.scan(file: file).completed)
        XCTAssertFalse(rule.scan(file: file, timeout: 0).completed)
        XCTAssertFalse(rule.scan(file: file, timeout: -1).completed)
        XCTAssertTrue(ProtectionScanner.Summary().incomplete)
        XCTAssertFalse(ProtectionScanner.Summary(catalogVersion: 1).incomplete)
        XCTAssertTrue(ProtectionScanner.Summary(catalogVersion: 1, issues: ["failed"]).incomplete)
    }
}
