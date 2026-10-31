import XCTest
@testable import Squeaky

final class ProtectionTests: XCTestCase {
    func testOwnershipRequiresPathBoundary() {
        let owner = URL(fileURLWithPath: "/Applications/Bad.app")
        for suffix in ["", "/Contents/MacOS/bad"] {
            XCTAssertTrue(ProtectionScanner.owns(program: URL(fileURLWithPath: owner.path + suffix), owner: owner))
        }
        for suffix in ["2", "Backup/Contents/MacOS/good", ".other", "-safe"] {
            XCTAssertFalse(ProtectionScanner.owns(program: URL(fileURLWithPath: owner.path + suffix), owner: owner))
        }
    }
}
