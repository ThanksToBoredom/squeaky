import XCTest
@testable import Squeaky

final class FileSafetyTests: XCTestCase {
    func testRemovalBoundaries() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("home")
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for name in ["", "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Applications", ".Trash", "Library/Caches", "Library/Logs", "Library/Application Support", "Library/Preferences", "Library/Containers", "Library/Group Containers", "Library/Mail"] {
            XCTAssertFalse(FileUtils.isSafeToRemove(home.appendingPathComponent(name), home: home), name)
        }
        XCTAssertTrue(FileUtils.isSafeToRemove(home.appendingPathComponent("Documents/file"), home: home))
        XCTAssertFalse(FileUtils.isSafeToRemove(outside, home: home))
        let link = home.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertTrue(FileUtils.isSafeToRemove(link, home: home))
        XCTAssertFalse(FileUtils.isSafeToRemove(link.appendingPathComponent("file"), home: home))
        let alias = home.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: home)
        XCTAssertFalse(FileUtils.isSafeToRemove(alias.appendingPathComponent("Documents"), home: home))
        XCTAssertFalse(FileUtils.isSafeToRemove(URL(string: "https://example.org/file")!, home: home))
        XCTAssertTrue(FileUtils.isSafeToRemove(URL(fileURLWithPath: "/Applications/Example.app"), home: home))
        XCTAssertFalse(FileUtils.isSafeToRemove(URL(fileURLWithPath: "/Applications/Example.app/Contents/Helper.app"), home: home))
    }
}
