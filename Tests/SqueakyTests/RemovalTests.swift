import XCTest
@testable import Squeaky

final class RemovalTests: XCTestCase {
    func testFailedPrimaryPreservesExtrasAndMissingDoesNotCount() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/removal-" + UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let extra = root.appendingPathComponent("extra")
        try Data([1]).write(to: extra)
        for primary in [URL(fileURLWithPath: "/System/refused"), root.appendingPathComponent("missing")] {
            let result = FileOps.remove([RemovalRequest(url: primary, extras: [extra], size: 100, method: .delete)])
            XCTAssertEqual(result.removed, 0)
            XCTAssertEqual(result.freed, 0)
            XCTAssertFalse(result.failures.isEmpty)
            XCTAssertTrue(fm.fileExists(atPath: extra.path))
        }
        let cancel = CancelToken(); cancel.cancel()
        XCTAssertTrue(FileOps.remove([RemovalRequest(url: extra, extras: [], size: 1, method: .delete)], cancel: cancel).cancelled)
        XCTAssertTrue(fm.fileExists(atPath: extra.path))
        let request = RemovalRequest(url: extra, extras: [], size: 100, method: .delete)
        let result = FileOps.remove([request, request])
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.removedURLs, [extra])
        XCTAssertFalse(fm.fileExists(atPath: extra.path))
        XCTAssertEqual(FileOps.remove([]).removed, 0)
    }
}
