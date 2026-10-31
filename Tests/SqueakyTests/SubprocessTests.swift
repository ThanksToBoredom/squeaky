import XCTest
@testable import Squeaky

final class SubprocessTests: XCTestCase {
    func testDrainsLargeStderrWithoutBlockingStdout() {
        let result = StartupInspector.run("/bin/sh", ["-c", "head -c 262144 /dev/zero >&2; printf done"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "done")
        XCTAssertEqual(result.error.utf8.count, 262144)
    }
    func testLaunchFailureAndNonzeroExit() {
        XCTAssertEqual(StartupInspector.run("/does/not/exist", []).status, -1)
        let result = StartupInspector.run("/bin/sh", ["-c", "printf failure >&2; exit 7"])
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.error, "failure")
        XCTAssertTrue(result.output.isEmpty)
    }
}
