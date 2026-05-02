#if canImport(AppKit) && os(macOS)
import Testing
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
@MainActor
@Suite(.serialized) struct MarginaliaTextViewMacTests {

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

    @Test func typingDoesNotResetCursorWithConstantSelection() throws {
        let (_, textView, coord) = try makeStack(
            text: .constant("hello"),
            selection: .constant(NSRange(location: 0, length: 0))
        )

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        fireSelectionChanged(textView, on: coord)

        coord.apply(
            text: "hello",
            selection: NSRange(location: 0, length: 0),
            to: textView
        )

        #expect(
            textView.selectedRange() == NSRange(location: 5, length: 0),
            "Cursor must remain where the user put it; the constant (0,0) binding must not snap it back."
        )
        #expect(
            coord.lastAppliedSelection == NSRange(location: 0, length: 0),
            "lastAppliedSelection must track the binding, never the user-driven cursor."
        )
    }

    @Test func typingDoesNotPrependWithConstantBinding() throws {
        let (c, textView, coord) = try makeStack(
            text: .constant("hello"),
            selection: .constant(NSRange(location: 0, length: 0))
        )

        let endLocation = (c.text as NSString).length
        textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        fireSelectionChanged(textView, on: coord)

        for char in ["a", "b", "c"] {
            let cursor = textView.selectedRange().location
            c.textStorage.replaceCharacters(in: NSRange(location: cursor, length: 0), with: char)
            textView.setSelectedRange(NSRange(location: cursor + 1, length: 0))
            fireTextChanged(textView, on: coord)
            fireSelectionChanged(textView, on: coord)

            coord.apply(
                text: "hello",
                selection: NSRange(location: 0, length: 0),
                to: textView
            )
        }

        #expect(c.text == "helloabc", "Characters should append, not prepend.")
    }

    // MARK: - external binding changes still propagate

    @Test func externalSelectionChangeIsApplied() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (_, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        selBox.value = NSRange(location: 2, length: 0)
        coord.apply(text: textBox.value, selection: selBox.value, to: textView)

        #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
        #expect(coord.lastAppliedSelection == NSRange(location: 2, length: 0))
    }

    @Test func externalTextChangeIsApplied() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (c, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        textBox.value = "world"
        coord.apply(text: textBox.value, selection: selBox.value, to: textView)

        #expect(c.text == "world")
        #expect(textView.string == "world")
        #expect(coord.lastAppliedText == "world")
    }

    // MARK: - redundant-apply skip

    @Test func redundantApplyDoesNotMoveCursor() throws {
        let (_, textView, coord) = try makeStack(
            text: .constant("hello"),
            selection: .constant(NSRange(location: 0, length: 0))
        )

        coord.apply(text: "hello", selection: NSRange(location: 0, length: 0), to: textView)

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        fireSelectionChanged(textView, on: coord)

        coord.apply(text: "hello", selection: NSRange(location: 0, length: 0), to: textView)

        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    // MARK: - delegate writes propagate to bindings

    @Test func delegateWritesPropagateToBindings() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (c, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        fireSelectionChanged(textView, on: coord)
        #expect(selBox.value == NSRange(location: 3, length: 0))
        #expect(c.selection == NSRange(location: 3, length: 0))

        c.textStorage.replaceCharacters(in: NSRange(location: 3, length: 0), with: "X")
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        fireTextChanged(textView, on: coord)
        #expect(textBox.value == "helXlo")
    }

    // MARK: - apply is suppressed during its own delegate echo

    @Test func applyDoesNotEchoBackThroughDelegate() throws {
        let textBox = Box("hello")
        let selBox = Box(NSRange(location: 0, length: 0))

        let (_, textView, coord) = try makeStack(
            text: makeBinding(textBox),
            selection: makeBinding(selBox)
        )

        selBox.value = NSRange(location: 2, length: 0)
        coord.apply(text: textBox.value, selection: selBox.value, to: textView)

        #expect(selBox.value == NSRange(location: 2, length: 0))
    }

    // MARK: - list continuation lands in a state that's stable on re-render

    @Test func listContinuationLeavesSelectionStableOnReRender() throws {
        let (c, textView, coord) = try makeStack(
            text: .constant("- item"),
            selection: .constant(NSRange(location: 0, length: 0)),
            initialText: "- item"
        )
        let endLocation = (c.text as NSString).length
        textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        fireSelectionChanged(textView, on: coord)

        let handled = coord.textView(
            textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )
        #expect(handled, "Return on a list line should be handled by ListContinuation.")
        #expect(c.text == "- item\n- ")
        let expectedCursor = ("- item\n- " as NSString).length
        #expect(textView.selectedRange() == NSRange(location: expectedCursor, length: 0))

        coord.apply(
            text: c.text,
            selection: NSRange(location: 0, length: 0),
            to: textView
        )
        #expect(
            textView.selectedRange() == NSRange(location: expectedCursor, length: 0),
            "ListContinuation result must survive a stale-binding re-render."
        )
    }
}
#endif
