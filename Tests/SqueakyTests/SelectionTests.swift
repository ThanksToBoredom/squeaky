import XCTest
@testable import Squeaky

final class SelectionTests: XCTestCase {
    @MainActor func testSelectionAndExtras() {
        let model = ModuleModel(module: .cleanup, scanner: { _ in [] })
        let extra = ExtraFile(url: URL(fileURLWithPath: "/example/extra"), size: 5)
        let item = CleanItem(url: URL(fileURLWithPath: "/example/file"), name: "file", size: 10, extras: [extra], removal: .delete)
        let category = ScanCategory(id: "one", title: "Files", description: "", symbol: "", items: [item])
        model.categories = [category, ScanCategory(id: "two", title: "Files", description: "", symbol: "", items: [item])]
        XCTAssertEqual(model.items().count, 1)
        XCTAssertEqual(model.totalSize, 15)
        XCTAssertEqual(model.selectedSize(), 0)
        model.requestClean()
        XCTAssertNil(model.pendingClean)
        model.toggle(item)
        XCTAssertEqual(model.selectedSize(), 15)
        XCTAssertEqual(model.checkState(for: category), .on)
        model.toggleExtra(extra)
        XCTAssertEqual(model.selectedSize(), 10)
        model.toggleExtra(extra)
        XCTAssertEqual(model.selectedSize(), 15)
        model.setAll(category, selected: false)
        XCTAssertEqual(model.checkState(for: category), .off)
        XCTAssertTrue(model.selectedItems().isEmpty)
        XCTAssertTrue(model.items(in: ["missing"]).isEmpty)
        model.phase = .working
        model.review(nil)
        XCTAssertEqual(model.phase, .working)
        model.startOver()
        XCTAssertEqual(model.phase, .working)
    }
    @MainActor func testRemovalRefusesScanningModule() async {
        let model = ModuleModel(module: .cleanup, scanner: { _ in [] })
        model.phase = .scanning
        let result = await model.removeSelected()
        XCTAssertFalse(result.failures.isEmpty)
        XCTAssertEqual(model.phase, .scanning)
    }
}
