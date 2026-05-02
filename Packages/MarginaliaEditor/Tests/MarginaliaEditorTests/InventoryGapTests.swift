#if canImport(AppKit) && os(macOS)
import Testing
import AppKit
import SwiftUI
import MarginaliaSyntax
@testable import MarginaliaView
@testable import MarginaliaEditor

@MainActor
@Suite(.serialized) struct MarginaliaInventoryGapTests {

    @Test(arguments: 1...6) func headingActionAppliesAllSixLevels(level: Int) throws {
        let c = try EditorController(initialText: "title")
        c.selection = NSRange(location: 0, length: 5)
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.heading(level: level), controller: c, text: bind(textBox), showPreview: sp)

        let prefix = String(repeating: "#", count: level) + " "
        #expect(c.text == prefix + "title")
    }

    @Test func linkActionWrapsSelectionAsLabelPlaceholder() throws {
        let c = try EditorController(initialText: "click here")
        c.selection = NSRange(location: 0, length: 5)
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.link, controller: c, text: bind(textBox), showPreview: sp)

        #expect(c.text == "[click](url) here")
    }

    @Test func codeBlockActionWrapsSelectionInTripleBacktickFence() throws {
        let c = try EditorController(initialText: "let x = 1")
        c.selection = NSRange(location: 0, length: 9)
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.codeBlock, controller: c, text: bind(textBox), showPreview: sp)

        #expect(c.text.contains("```"))
        #expect(c.text.contains("let x = 1"))
    }

    @Test func textViewSmartQuotesAndDashesStayDisabled() throws {
        let c = try EditorController(initialText: "")
        let textView = MarginaliaNSTextView(frame: .zero, textContainer: c.textContainer)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        #expect(textView.isAutomaticQuoteSubstitutionEnabled == false)
        #expect(textView.isAutomaticDashSubstitutionEnabled == false)
        #expect(textView.isAutomaticTextReplacementEnabled == false)
    }

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
}
#endif
