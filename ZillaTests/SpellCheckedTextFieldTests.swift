#if os(macOS)
import AppKit
import Testing
@testable import Zilla

@MainActor
@Suite struct SpellCheckedTextFieldTests {
    private func hostedField() -> (NSWindow, SpellCheckingNSTextField) {
        let field = SpellCheckingNSTextField()
        field.stringValue = "Recieve the notifcation"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(field)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        return (window, field)
    }

    @Test func editingEnablesContinuousSpellChecking() {
        let (window, field) = hostedField()
        #expect(window.makeFirstResponder(field))
        let editor = field.currentEditor() as? NSTextView
        #expect(editor?.isContinuousSpellCheckingEnabled == true)
    }

    @Test func endingEditingLeavesTheSharedFieldEditorUnchecked() {
        let (window, field) = hostedField()
        #expect(window.makeFirstResponder(field))
        let editor = field.currentEditor() as? NSTextView
        #expect(window.makeFirstResponder(nil))
        #expect(editor?.isContinuousSpellCheckingEnabled == false)
    }
}
#endif
