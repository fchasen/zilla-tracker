import XCTest
@testable import FolioCodeView

final class FolioTextMetricsTests: XCTestCase {
    func testEmptyTextHasOneLine() {
        XCTAssertEqual(FolioTextMetrics.lineCount(in: ""), 1)
    }

    func testSingleLineTextHasOneLine() {
        XCTAssertEqual(FolioTextMetrics.lineCount(in: "let value = 1;"), 1)
    }

    func testMultilineTextCountsNewlines() {
        XCTAssertEqual(FolioTextMetrics.lineCount(in: "a\nb\nc"), 3)
    }

    func testTrailingNewlineCountsEmptyFinalLine() {
        XCTAssertEqual(FolioTextMetrics.lineCount(in: "a\n"), 2)
    }
}
