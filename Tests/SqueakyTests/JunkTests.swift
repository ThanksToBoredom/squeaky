import XCTest
@testable import Squeaky

final class JunkTests: XCTestCase {
    func testPartialDownloadsAreNeverPreselected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, ext) in ["download", "crdownload", "part", "partial", "opdownload", "PART", "txt"].enumerated() {
            try Data(repeating: 1, count: 4096).write(to: downloads.appendingPathComponent("file-\(index)." + ext))
        }
        let categories = await JunkScanner.scan(ProgressReporter(), home: root)
        let partials = try XCTUnwrap(categories.first { $0.id == "broken-downloads" })
        XCTAssertEqual(partials.items.count, 6)
        XCTAssertTrue(partials.items.allSatisfy { !$0.selectedByDefault && $0.removal == .trash })
    }
}
