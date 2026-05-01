import XCTest
@testable import MarginaliaView

final class MarginaliaViewSmokeTests: XCTestCase {
    func testHighlighterInitializes() throws {
        let h = try Highlighter(dialect: .commonMark)
        XCTAssertEqual(h.dialect, .commonMark)
    }

    func testHighlighterEmitsRunsForBoldText() throws {
        let h = try Highlighter(dialect: .commonMark)
        let runs = h.runs(for: "**bold**")
        XCTAssertFalse(runs.isEmpty)
    }
}
