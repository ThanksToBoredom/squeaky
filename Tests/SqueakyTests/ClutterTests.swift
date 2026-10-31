import XCTest
@testable import Squeaky

final class ClutterTests: XCTestCase {
    func testSizeThresholdsAndDuplicateKeeper() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = root.appendingPathComponent("Downloads")
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for size in [1048575, 1048576, 1048577] {
            for name in ["a", "b"] {
                let file = downloads.appendingPathComponent("\(size)-\(name)")
                try Data(repeating: 65, count: size).write(to: file)
                try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: file.path)
            }
        }
        for size in [104857599, 104857600, 104857601] {
            let file = downloads.appendingPathComponent("large-\(size)")
            fm.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
        }
        let result = await ClutterScanner.scan(ProgressReporter(), home: root)
        let duplicates = try XCTUnwrap(result.first { $0.id == "duplicates" }).items
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertTrue(duplicates.allSatisfy { $0.url.lastPathComponent.hasSuffix("-b") && $0.selectedByDefault && $0.duplicateOriginal != nil })
        let large = try XCTUnwrap(result.first { $0.id == "large" }).items
        XCTAssertEqual(large.map(\.size), [104857601, 104857600])
        XCTAssertTrue(large.allSatisfy { !$0.selectedByDefault })
    }
    func testChangedDuplicateIsPreserved() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/duplicates-" + UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("original"), copy = root.appendingPathComponent("copy")
        try Data([1]).write(to: original)
        try Data([2]).write(to: copy)
        let request = RemovalRequest(url: copy, extras: [], size: 1, method: .delete, duplicateOriginal: original)
        XCTAssertEqual(FileOps.remove([request]).removed, 0)
        XCTAssertTrue(fm.fileExists(atPath: copy.path))
        try fm.removeItem(at: original)
        XCTAssertEqual(FileOps.remove([request]).removed, 0)
        try Data([2]).write(to: original)
        XCTAssertEqual(FileOps.remove([request]).removed, 1)
        XCTAssertTrue(fm.fileExists(atPath: original.path))
    }
}
