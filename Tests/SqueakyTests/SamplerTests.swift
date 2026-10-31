import XCTest
@testable import Squeaky

final class SamplerTests: XCTestCase {
    func testTickBoundaries() {
        let previous = SystemSample(busyTicks: 100, totalTicks: 200)
        XCTAssertNil(SystemSampler.cpuFraction(current: previous, previous: nil))
        for total: UInt64 in [0, 199, 200] {
            XCTAssertNil(SystemSampler.cpuFraction(current: SystemSample(busyTicks: 100, totalTicks: total), previous: previous))
        }
        XCTAssertNil(SystemSampler.cpuFraction(current: SystemSample(busyTicks: 99, totalTicks: 201), previous: previous))
        for (busy, expected): (UInt64, Double) in [(100, 0), (101, 0.5), (102, 1), (103, 1)] {
            XCTAssertEqual(SystemSampler.cpuFraction(current: SystemSample(busyTicks: busy, totalTicks: 202), previous: previous), expected)
        }
    }
    func testProcessBoundaries() throws {
        XCTAssertTrue(SystemSampler.usage(current: SystemSample(), previous: nil, elapsedNanos: 0).isEmpty)
        let reading = ProcessReading(path: "/Applications/Foo.app/Contents/MacOS/foo", cpuNanos: 10, resident: 1024)
        let current = SystemSample(processes: [1: reading, 2: reading])
        let usage = try XCTUnwrap(SystemSampler.usage(current: current, previous: nil, elapsedNanos: 0).first)
        XCTAssertEqual(usage.processCount, 2)
        XCTAssertEqual(usage.memory, 2048)
        XCTAssertNil(usage.cpu)
        XCTAssertEqual(usage.id, "/Applications/Foo.app")
        XCTAssertNil(SystemSampler.appBundlePath(for: "/usr/bin/tool"))
        XCTAssertEqual(SystemSampler.appBundlePath(for: "/A.app/Contents/B.app/Contents/MacOS/b"), "/A.app")
    }
}
