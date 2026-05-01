#if canImport(AppKit) && os(macOS)
import XCTest
import AppKit
import MarginaliaSyntax
@testable import MarginaliaView

/// `EditorSizing.fitsContent` is the user-visible promise: the editor grows
/// taller as the user types, instead of scrolling internally. The mechanic
/// is `MarginaliaNSTextView.intrinsicContentSize` returning the laid-out
/// content height — SwiftUI then uses that to size the representable.
final class IntrinsicSizeTests: XCTestCase {

    private func makeTextView(width: CGFloat = 200) throws -> (EditorController, MarginaliaNSTextView) {
        let c = try EditorController(initialText: "")
        c.textContainer.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        let textView = MarginaliaNSTextView(frame: .zero, textContainer: c.textContainer)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.fitsContent = true
        c.intrinsicSizeInvalidator = { [weak textView] in
            textView?.invalidateIntrinsicContentSize()
        }
        return (c, textView)
    }

    func testEmptyEditorHasNonZeroIntrinsicHeight() throws {
        let (_, textView) = try makeTextView()
        XCTAssertGreaterThan(textView.intrinsicContentSize.height, 0)
    }

    func testIntrinsicHeightGrowsWithMoreLines() throws {
        let (c, textView) = try makeTextView()
        let oneLine = textView.intrinsicContentSize.height

        c.setText("line 1\nline 2\nline 3\nline 4\nline 5\n")
        c.refreshNow()

        let manyLines = textView.intrinsicContentSize.height
        XCTAssertGreaterThan(manyLines, oneLine)
    }

    func testIntrinsicWidthIsNoIntrinsicMetric() throws {
        let (_, textView) = try makeTextView()
        XCTAssertEqual(textView.intrinsicContentSize.width, NSView.noIntrinsicMetric)
    }

    func testFitsContentDisabledFallsBackToSuper() throws {
        let (_, textView) = try makeTextView()
        textView.fitsContent = false
        // NSTextView's default intrinsicContentSize returns
        // (noIntrinsicMetric, noIntrinsicMetric) when neither dimension is
        // tracked — we just verify we're not returning the fitsContent
        // computed height anymore.
        XCTAssertEqual(textView.intrinsicContentSize.height, NSView.noIntrinsicMetric)
    }

    func testIntrinsicSizeInvalidatorFiresOnStorageChange() throws {
        let c = try EditorController(initialText: "")
        var fired = 0
        c.intrinsicSizeInvalidator = { fired += 1 }
        c.setText("hello")
        XCTAssertGreaterThan(fired, 0)
    }

    // MARK: - minimumIntrinsicHeight

    func testMinimumIntrinsicHeightFloorsEmptyEditor() throws {
        let (_, textView) = try makeTextView()
        textView.minimumIntrinsicHeight = 200
        XCTAssertEqual(textView.intrinsicContentSize.height, 200, accuracy: 1)
    }

    func testIntrinsicHeightStillGrowsBeyondMinimum() throws {
        let (c, textView) = try makeTextView()
        textView.minimumIntrinsicHeight = 50
        let lots = Array(repeating: "a long line of text that fills width", count: 12).joined(separator: "\n")
        c.setText(lots)
        c.refreshNow()
        XCTAssertGreaterThan(textView.intrinsicContentSize.height, 50)
    }
}
#endif
