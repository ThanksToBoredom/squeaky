import XCTest
@testable import Squeaky

private actor ScanGate {
    var continuations: [CheckedContinuation<[ScanCategory], Never>] = []
    func scan() async -> [ScanCategory] {
        await withCheckedContinuation { continuations.append($0) }
    }
    var count: Int { continuations.count }
    func finish(_ index: Int) { continuations[index].resume(returning: []) }
}

final class ScanStateTests: XCTestCase {
    @MainActor func testSupersededScanCannotResetNewScan() async {
        let gate = ScanGate()
        let model = ModuleModel(module: .cleanup, scanner: { _ in await gate.scan() })
        let first = Task { await model.scan() }
        while await gate.count < 1 { await Task.yield() }
        let second = Task { await model.scan() }
        while await gate.count < 2 { await Task.yield() }
        await gate.finish(0)
        await first.value
        XCTAssertEqual(model.phase, .scanning)
        await gate.finish(1)
        await second.value
        XCTAssertEqual(model.phase, .results)
    }
    @MainActor func testStartOverInvalidatesInFlightScan() async {
        let gate = ScanGate()
        let model = ModuleModel(module: .cleanup, scanner: { _ in await gate.scan() })
        let task = Task { await model.scan() }
        while await gate.count < 1 { await Task.yield() }
        model.startOver()
        await gate.finish(0)
        await task.value
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.categories.isEmpty)
    }
}
