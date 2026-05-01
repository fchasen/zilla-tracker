#if canImport(AppKit) && os(macOS)
import XCTest
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
final class MarginaliaToolbarActionsTests: XCTestCase {

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

    // MARK: - selection-aware wraps

    func testBoldWrapsSelection() throws {
        let c = try EditorController(initialText: "hello world")
        c.selection = NSRange(location: 6, length: 5)  // "world"
        let textBox = Box("hello world")
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.bold, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertEqual(c.text, "hello **world**")
        XCTAssertEqual(textBox.value, "hello **world**")
    }

    func testItalicWrapsSelection() throws {
        let c = try EditorController(initialText: "hello world")
        c.selection = NSRange(location: 0, length: 5)  // "hello"
        let textBox = Box("hello world")
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.italic, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertEqual(c.text, "*hello* world")
    }

    func testStrikethroughWrapsSelection() throws {
        let c = try EditorController(initialText: "hello world")
        c.selection = NSRange(location: 6, length: 5)
        let textBox = Box("hello world")
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.strikethrough, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertEqual(c.text, "hello ~~world~~")
    }

    func testCodeSpanWrapsSelection() throws {
        let c = try EditorController(initialText: "this is some code test")
        c.selection = NSRange(location: 8, length: 9)  // "some code"
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.codeSpan, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertEqual(c.text, "this is `some code` test")
    }

    // MARK: - HR works

    func testHorizontalRuleInserts() throws {
        let c = try EditorController(initialText: "hello")
        c.selection = NSRange(location: 5, length: 0)
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.horizontalRule, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertTrue(c.text.contains("---"))
    }

    // MARK: - crash protection

    func testTaskListWithStaleOutOfBoundsSelectionDoesNotCrash() throws {
        // Reproduces the user's `NSRangeException` from the original report:
        // selection of {159, 28} into a 6-char text.
        let c = try EditorController(initialText: "")
        c.selection = NSRange(location: 159, length: 28)
        let textBox = Box(c.text)
        let (_, sp) = showPreviewBinding()

        // Must not crash.
        MarginaliaToolbarActions.perform(.taskList, controller: c, text: bind(textBox), showPreview: sp)
        XCTAssertTrue(c.text.contains("- [ ] "))
    }

    // MARK: - quote/list don't resurrect deleted text

    func testQuoteUsesControllerStateNotStaleText() throws {
        // Simulate: user had "lorem ipsum dolor sit", deleted everything,
        // then clicked Quote. The toolbar must compute against the empty
        // current text, not the prior longer text.
        let c = try EditorController(initialText: "lorem ipsum dolor sit")
        // user deletes
        c.setText("")
        c.selection = NSRange(location: 0, length: 0)
        let textBox = Box("")
        let (_, sp) = showPreviewBinding()

        MarginaliaToolbarActions.perform(.blockquote, controller: c, text: bind(textBox), showPreview: sp)

        XCTAssertFalse(c.text.contains("lorem"), "Quote must not bring deleted text back: \(c.text)")
        XCTAssertTrue(c.text.hasPrefix("> "))
    }

    // MARK: - togglePreview only flips showPreview

    func testTogglePreviewFlipsBinding() throws {
        let c = try EditorController(initialText: "")
        let (showBox, sp) = showPreviewBinding()
        XCTAssertFalse(showBox.value)

        MarginaliaToolbarActions.perform(.togglePreview, controller: c, text: bind(Box("")), showPreview: sp)

        XCTAssertTrue(showBox.value)
    }

    func testTogglePreviewCanFlipBackToFalse() throws {
        // The previously-reported "stuck in preview" bug: pressing the
        // toggle when already in preview must take us back out.
        let c = try EditorController(initialText: "")
        let (showBox, sp) = showPreviewBinding()
        showBox.value = true

        MarginaliaToolbarActions.perform(.togglePreview, controller: c, text: bind(Box("")), showPreview: sp)

        XCTAssertFalse(showBox.value)
    }
}
#endif
