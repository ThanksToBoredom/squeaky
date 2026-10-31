import XCTest
import SQLite3
@testable import Squeaky

final class CatalogTests: XCTestCase {
    func testAbsentMalformedAndPartialDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = XProtectCatalog(resources: root, version: 1, updated: nil)
        XCTAssertTrue(catalog.yaraSources.isEmpty)
        XCTAssertTrue(catalog.blockedSafariExtensions.isEmpty)
        XCTAssertTrue(catalog.gatekeeperBlocklist().hashes.isEmpty)
        XCTAssertFalse(catalog.gatekeeperBlocklist().complete)
        let file = root.appendingPathComponent("gk.db")
        try Data("invalid sqlite".utf8).write(to: file)
        XCTAssertTrue(catalog.gatekeeperBlocklist().teams.isEmpty)
        try FileManager.default.removeItem(at: file)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE blocked_teams(team_id TEXT); INSERT INTO blocked_teams VALUES ('TEAM'), (NULL);", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(catalog.gatekeeperBlocklist().teams, ["TEAM"])
        XCTAssertTrue(catalog.gatekeeperBlocklist().hashes.isEmpty)
        XCTAssertFalse(catalog.gatekeeperBlocklist().complete)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE blocked_hashes(hash BLOB);", nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(catalog.gatekeeperBlocklist().complete)
    }
}
