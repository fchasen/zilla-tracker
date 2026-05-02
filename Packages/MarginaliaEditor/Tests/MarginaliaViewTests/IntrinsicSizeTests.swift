#if canImport(AppKit) && os(macOS)
import Testing
import AppKit
import MarginaliaSyntax
@testable import MarginaliaView

/// `EditorSizing.fitsContent` is the user-visible promise: the editor grows
/// taller as the user types, instead of scrolling internally. The mechanic
/// is `MarginaliaNSTextView.intrinsicContentSize` returning the laid-out
/// content height — SwiftUI then uses that to size the representable.
@MainActor
@Suite(.serialized) struct IntrinsicSizeTests {

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

    @Test func emptyEditorHasNonZeroIntrinsicHeight() throws {
        let (_, textView) = try makeTextView()
        #expect(textView.intrinsicContentSize.height > 0)
    }

    @Test func intrinsicHeightGrowsWithMoreLines() throws {
        let (c, textView) = try makeTextView()
        let oneLine = textView.intrinsicContentSize.height

        c.setText("line 1\nline 2\nline 3\nline 4\nline 5\n")
        c.refreshNow()

        let manyLines = textView.intrinsicContentSize.height
        #expect(manyLines > oneLine)
    }

    @Test func intrinsicWidthIsNoIntrinsicMetric() throws {
        let (_, textView) = try makeTextView()
        #expect(textView.intrinsicContentSize.width == NSView.noIntrinsicMetric)
    }

    @Test func fitsContentDisabledFallsBackToSuper() throws {
        let (_, textView) = try makeTextView()
        textView.fitsContent = false
        #expect(textView.intrinsicContentSize.height == NSView.noIntrinsicMetric)
    }

    @Test func intrinsicSizeInvalidatorFiresOnStorageChange() throws {
        let c = try EditorController(initialText: "")
        var fired = 0
        c.intrinsicSizeInvalidator = { fired += 1 }
        c.setText("hello")
        #expect(fired > 0)
    }

    // MARK: - minimumIntrinsicHeight

    @Test func minimumIntrinsicHeightFloorsEmptyEditor() throws {
        let (_, textView) = try makeTextView()
        textView.minimumIntrinsicHeight = 200
        #expect(abs(textView.intrinsicContentSize.height - 200) < 1)
    }

    @Test func intrinsicHeightStillGrowsBeyondMinimum() throws {
        let (c, textView) = try makeTextView()
        textView.minimumIntrinsicHeight = 50
        let lots = Array(repeating: "a long line of text that fills width", count: 12).joined(separator: "\n")
        c.setText(lots)
        c.refreshNow()
        #expect(textView.intrinsicContentSize.height > 50)
    }
}
#endif
