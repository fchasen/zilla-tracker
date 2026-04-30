#if canImport(AppKit) && os(macOS)
import XCTest
import AppKit
import SwiftUI
import MarginaliaSyntax
@testable import MarginaliaView

/// Regression tests for the binding↔NSTextView sync inside
/// `MarginaliaTextViewMac.Coordinator`. The bug they exist to prevent: typing
/// snaps the cursor back to (0,0) — and therefore appends every typed
/// character to the front of the string — when SwiftUI re-renders the
/// representable while the `selection` binding is still stale (the most
/// common case being the `.constant(NSRange(0, 0))` default).
final class MarginaliaTextViewMacTests: XCTestCase {

    // MARK: - helpers

    private final class Box<T> {
        var value: T
        init(_ v: T) { value = v }
    }

    private func makeBinding<T>(_ box: Box<T>) -> Binding<T> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }

    /// Set up a (controller, textView, coordinator) triple wired the way the
    /// representable wires them in production, with bindings the caller
    /// supplies.
    private func makeStack(
        text: Binding<String>,
        selection: Binding<NSRange>,
        initialText: String = "hello"
    ) throws -> (EditorController, NSTextView, MarginaliaTextViewMac.Coordinator) {
        let c = try EditorController(initialText: initialText)
        let parent = MarginaliaTextViewMac(controller: c, text: text, selection: selection)
        let coordinator = MarginaliaTextViewMac.Coordinator(parent)
        let textView = MarginaliaNSTextView(frame: .zero, textContainer: c.textContainer)
        textView.delegate = coordinator
        coordinator.textView = textView
        return (c, textView, coordinator)
    }

    private func fireSelectionChanged(_ textView: NSTextView, on coord: MarginaliaTextViewMac.Coordinator) {
        coord.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )
    }

    private func fireTextChanged(_ textView: NSTextView, on coord: MarginaliaTextViewMac.Coordinator) {
        coord.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )
    }

    // MARK: - the regression: typing must not reset the cursor

    func testTypingDoesNotResetCursorWithConstantSelection() throws {
        let (_, textView, coord) = try makeStack(
            text: .constant("hello"),
            selection: .constant(NSRange(location: 0, length: 0))
        )

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        fireSelectionChanged(textView, on: coord)

        // SwiftUI re-renders updateNSView with the still-stale constant binding.
        coord.apply(
            text: "hello",
            selection: NSRange(location: 0, length: 0),
            to: textView
        )

        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: 5, length: 0),
            "Cursor must remain where the user put it; the constant (0,0) binding must not snap it back."
        )
        XCTAssertEqual(
            coord.lastAppliedSelection,
            NSRange(location: 0, length: 0),
            "lastAppliedSelection must track the binding, never the user-driven cursor."
        )
    }

    func testTypingDoesNotPrependWithConstantBinding() throws {
        let (c, textView, coord) = try makeStack(
            text: .constant("hello"),
            selection: .constant(NSRange(location: 0, length: 0))
        )

        // Position cursor at the end and type three characters, with a re-render
        // (`apply` with stale binding) interleaved between each keystroke — the
        // pattern that produced "cbahello" before the fix.
        let endLocation = (c.text as NSString).length
        textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        fireSelectionChanged(textView, on: coord)

        for char in ["a", "b", "c"] {
            let cursor = textView.selectedRange().location
            c.textStorage.replaceCharacters(in: NSRange(location: cursor, length: 0), with: char)
            textView.setSelectedRange(NSRange(location: cursor + 1, length: 0))
            fireTextChanged(textView, on: coord)
            fireSelectionChanged(textView, on: coord)

            // Stale-binding re-render between each keystroke.
            coord.apply(
                text: "hello",
                selection: NSRange(location: 0, length: 0),
                to: textView
            )
        }

        XCTAssertEqual(c.text, "helloabc", "Characters should append, not prepend.")
    }

    // MARK: - external binding changes still propagate

    func testExternalSelectionChangeIsApplied() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (_, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        // External code moves the selection.
        selBox.value = NSRange(location: 2, length: 0)
        coord.apply(text: textBox.value, selection: selBox.value, to: textView)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(coord.lastAppliedSelection, NSRange(location: 2, length: 0))
    }

    func testExternalTextChangeIsApplied() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (c, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        textBox.value = "world"
        coord.apply(text: textBox.value, selection: selBox.value, to: textView)

        XCTAssertEqual(c.text, "world")
        XCTAssertEqual(textView.string, "world")
        XCTAssertEqual(coord.lastAppliedText, "world")
    }

    // MARK: - redundant-apply skip

    func testRedundantApplyDoesNotMoveCursor() throws {
        let (_, textView, coord) = try makeStack(
            text: .constant("hello"),
            selection: .constant(NSRange(location: 0, length: 0))
        )

        // First apply primes lastApplied state.
        coord.apply(text: "hello", selection: NSRange(location: 0, length: 0), to: textView)

        // Now the user moves the cursor.
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        fireSelectionChanged(textView, on: coord)

        // A second apply with identical binding values must not disturb the cursor.
        coord.apply(text: "hello", selection: NSRange(location: 0, length: 0), to: textView)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    // MARK: - delegate writes propagate to bindings

    func testDelegateWritesPropagateToBindings() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (c, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        // User moves cursor — should write through to selBox.
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        fireSelectionChanged(textView, on: coord)
        XCTAssertEqual(selBox.value, NSRange(location: 3, length: 0))
        XCTAssertEqual(c.selection, NSRange(location: 3, length: 0))

        // User types — should write through to textBox.
        c.textStorage.replaceCharacters(in: NSRange(location: 3, length: 0), with: "X")
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        fireTextChanged(textView, on: coord)
        XCTAssertEqual(textBox.value, "helXlo")
    }

    // MARK: - apply is suppressed during its own delegate echo

    func testApplyDoesNotEchoBackThroughDelegate() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (_, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        // External selection update.
        selBox.value = NSRange(location: 2, length: 0)
        coord.apply(text: textBox.value, selection: selBox.value, to: textView)

        // If `setSelectedRange` inside apply re-fires the delegate without the
        // isApplyingFromBinding guard, the delegate would write back to selBox
        // again — harmless on its own, but it would re-trigger an apply loop.
        // The guard means the box is set exactly once, by us.
        XCTAssertEqual(selBox.value, NSRange(location: 2, length: 0))
    }

    // MARK: - list continuation lands in a state that's stable on re-render

    func testListContinuationLeavesSelectionStableOnReRender() throws {
        let (c, textView, coord) = try makeStack(
            text: .constant("- item"),
            selection: .constant(NSRange(location: 0, length: 0)),
            initialText: "- item"
        )
        // Cursor at end of "- item"
        let endLocation = (c.text as NSString).length
        textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        fireSelectionChanged(textView, on: coord)

        let handled = coord.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )
        XCTAssertTrue(handled, "Return on a list line should be handled by ListContinuation.")
        XCTAssertEqual(c.text, "- item\n- ")
        let expectedCursor = ("- item\n- " as NSString).length
        XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedCursor, length: 0))

        // Now SwiftUI re-renders with the still-constant (0, 0) selection
        // binding. The new cursor must not be reset.
        coord.apply(
            text: c.text,
            selection: NSRange(location: 0, length: 0),
            to: textView
        )
        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: expectedCursor, length: 0),
            "ListContinuation result must survive a stale-binding re-render."
        )
    }
}
#endif
