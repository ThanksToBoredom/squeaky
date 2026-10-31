import XCTest
@testable import Squeaky

final class AppIdentifierTests: XCTestCase {
    func testByHostSuffixMustBeUUID() {
        for name in ["com.vendor.cafe", "com.vendor.deadbeef", "com.vendor.123", "com.vendor.", "com.vendor.-", "com.vendor.App"] {
            XCTAssertEqual(AppScanner.baseIdentifier(URL(fileURLWithPath: "/Library/Preferences/ByHost/" + name + ".plist")), name)
        }
        let uuid = "12345678-1234-1234-1234-123456789ABC"
        XCTAssertEqual(AppScanner.baseIdentifier(URL(fileURLWithPath: "/Library/Preferences/ByHost/com.vendor.App." + uuid + ".plist")), "com.vendor.App")
        for suffix in [".plist", ".savedState", ".binarycookies", ""] {
            XCTAssertEqual(AppScanner.baseIdentifier(URL(fileURLWithPath: "/Library/Preferences/com.vendor.App" + suffix)), "com.vendor.App")
        }
        XCTAssertEqual(AppScanner.baseIdentifier(URL(fileURLWithPath: "/Library/Preferences/com.vendor.App." + uuid + ".plist")), "com.vendor.App." + uuid)
    }
}
