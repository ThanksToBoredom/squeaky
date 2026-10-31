import XCTest
@testable import Squeaky

final class ArtworkTests: XCTestCase {
    @MainActor func testEmptyAndNegativeIconRequests() {
        XCTAssertTrue(IconWall.fileIcons(for: [], count: -1).isEmpty)
        XCTAssertTrue(IconWall.fileIcons(for: [], count: 0).isEmpty)
        XCTAssertTrue(IconWall.fileIcons(for: [], count: 1, fillers: []).isEmpty)
    }
}
