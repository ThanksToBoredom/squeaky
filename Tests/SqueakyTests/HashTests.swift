import XCTest
@testable import Squeaky

final class HashTests: XCTestCase {
    func testHashBoundaries() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        XCTAssertNil(FileUtils.sha256(of: file))
        XCTAssertNil(FileUtils.sha256(of: root)) // read error must not become the empty hash
        try Data("abc".utf8).write(to: file)
        XCTAssertNil(FileUtils.sha256(of: file, limit: -1))
        XCTAssertEqual(FileUtils.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(FileUtils.sha256(of: file, limit: 0), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        for size in [0, 1, 65535, 65536, 65537, 1048575, 1048576, 1048577] {
            try Data(repeating: 65, count: size).write(to: file)
            XCTAssertEqual(FileUtils.sha256(of: file), FileUtils.sha256(of: file, limit: size + 1))
            XCTAssertEqual(FileUtils.sha256(of: file), FileUtils.sha256(of: file, limit: size))
        }
    }
}
