#if canImport(AppKit) && os(macOS)
import Testing
import SwiftUI
import MarginaliaSyntax
import MarginaliaView
@testable import MarginaliaEditor

/// Tests the toolbar's action handler. The whole reason this lives behind
/// `MarginaliaToolbarActions.perform` (rather than reading its inputs from
/// SwiftUI bindings inside the toolbar struct itself) is the
/// `.constant(NSRange(0,0))` selection-binding default — when the toolbar
/// reads from a constant binding it always sees the cursor at 0, so wraps
/// like Bold/Italic apply to nothing instead of the user's selection.
/// These tests pin that the action handler reads `controller.selection`
/// (the live, delegate-updated truth) and writes back through the
/// controller — and that an out-of-bounds stale selection doesn't crash.
@MainActor
@Suite(.serialized) struct MarginaliaToolbarActionsTests {

    private final class Box<T> {
        var value: T
        init(_ v: T) { value = v }
    }

    private func bind<T>(_ box: Box<T>) -> Binding<T> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }

    // MARK: - selection-aware wraps

    @Test func boldWrapsSelection() throws {
        let c = try EditorController(initialText: "hello world")
        c.selection = NSRange(location: 6, length: 5)
        let textBox = Box("hello world")

        MarginaliaToolbarActions.perform(.bold, controller: c, text: bind(textBox))

        #expect(c.text == "hello **world**")
        #expect(textBox.value == "hello **world**")
    }

    @Test func italicWrapsSelection() throws {
        let c = try EditorController(initialText: "hello world")
        c.selection = NSRange(location: 0, length: 5)
        let textBox = Box("hello world")

        MarginaliaToolbarActions.perform(.italic, controller: c, text: bind(textBox))

        #expect(c.text == "*hello* world")
    }

    @Test func strikethroughWrapsSelection() throws {
        let c = try EditorController(initialText: "hello world")
        c.selection = NSRange(location: 6, length: 5)
        let textBox = Box("hello world")

        MarginaliaToolbarActions.perform(.strikethrough, controller: c, text: bind(textBox))

        #expect(c.text == "hello ~~world~~")
    }

    @Test func codeSpanWrapsSelection() throws {
        let c = try EditorController(initialText: "this is some code test")
        c.selection = NSRange(location: 8, length: 9)
        let textBox = Box(c.text)

        MarginaliaToolbarActions.perform(.codeSpan, controller: c, text: bind(textBox))

        #expect(c.text == "this is `some code` test")
    }

    // MARK: - HR works

    @Test func horizontalRuleInserts() throws {
        let c = try EditorController(initialText: "hello")
        c.selection = NSRange(location: 5, length: 0)
        let textBox = Box(c.text)

        MarginaliaToolbarActions.perform(.horizontalRule, controller: c, text: bind(textBox))

        #expect(c.text.contains("---"))
    }

    // MARK: - crash protection

    @Test func taskListWithStaleOutOfBoundsSelectionDoesNotCrash() throws {
        let c = try EditorController(initialText: "")
        c.selection = NSRange(location: 159, length: 28)
        let textBox = Box(c.text)

        MarginaliaToolbarActions.perform(.taskList, controller: c, text: bind(textBox))
        #expect(c.text.contains("- [ ] "))
    }

    // MARK: - quote/list don't resurrect deleted text

    @Test func quoteUsesControllerStateNotStaleText() throws {
        let c = try EditorController(initialText: "lorem ipsum dolor sit")
        c.setText("")
        c.selection = NSRange(location: 0, length: 0)
        let textBox = Box("")

        MarginaliaToolbarActions.perform(.blockquote, controller: c, text: bind(textBox))

        #expect(!c.text.contains("lorem"), "Quote must not bring deleted text back: \(c.text)")
        #expect(c.text.hasPrefix("> "))
    }

    // MARK: - selection coords through the source/display mapping

    @Test func italicInsideHeadingWysiwygWrapsSourceContent() throws {
        // Source `## Fred` displays as `Fred` in wysiwyg. The user clicks
        // the displayed `F` (display [0, 1)) — the platform view translates
        // that to source [3, 4) before storing in `controller.selection`.
        // The toolbar must operate on source coords, producing `## *F*red`,
        // NOT `##*F*red` (which is what it produced when selection was
        // misinterpreted as display coords).
        let c = try EditorController(initialText: "## Fred")
        c.refreshNow()
        c.selection = NSRange(location: 3, length: 1)
        let textBox = Box(c.text)

        MarginaliaToolbarActions.perform(.italic, controller: c, text: bind(textBox))

        #expect(c.text == "## *F*red")
    }
}
#endif
