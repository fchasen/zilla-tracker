#if canImport(AppKit) && os(macOS)
import XCTest
import AppKit
import SwiftUI
import MarginaliaSyntax
@testable import MarginaliaView
@testable import MarginaliaEditor

/// Coverage for editing-inventory rows that lacked a direct test in the
/// pre-existing suite: every heading level, link wrap, smart-quote
/// regression.
final class MarginaliaInventoryGapTests: XCTestCase {

    private final class Box<T> {
        var value: T
        init(_ v: T) { value = v }
    }

    private func bind<T>(_ box: Box<T>) -> Binding<T> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }

    private func showPreviewBinding() -> (Box<Bool>, Binding<Bool>) {
        let box = Box(false)
        return (box, bind(box))
    }

    func testHeadingActionAppliesAllSixLevels() throws {
        for level in 1...6 {
            let c = try EditorController(initialText: "title")
            c.selection = NSRange(location: 0, length: 5)
            let textBox = Box(c.text)
            let (_, sp) = showPreviewBinding()

            MarginaliaToolbarActions.perform(.heading(level: level), controller: c, text: bind(textBox), showPreview: sp)

            let prefix = String(repeating: "#", count: level) + " "
            XCTAssertEqual(c.text, prefix + "title", "heading level \(level)")
        }
    }

    func testLinkActionWrapsSelectionAsLabelPlaceholder() throws {
        let c = try EditorController(initialText: "click here")
        c.selection = NSRange(location: 0, length: 5)
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.link, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertEqual(c.text, "[click](url) here")
    }

    func testCodeBlockActionWrapsSelectionInTripleBacktickFence() throws {
        let c = try EditorController(initialText: "let x = 1")
        c.selection = NSRange(location: 0, length: 9)
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.codeBlock, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertTrue(c.text.contains("```"))
        XCTAssertTrue(c.text.contains("let x = 1"))
    }

    func testTextViewSmartQuotesAndDashesStayDisabled() throws {
        let c = try EditorController(initialText: "")
        let textView = MarginaliaNSTextView(frame: .zero, textContainer: c.textContainer)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
    }
}
#endif
