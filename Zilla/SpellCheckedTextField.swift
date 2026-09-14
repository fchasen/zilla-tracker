import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Plain, wrapping text input for single-value title fields (bug summaries)
/// with native spelling underlines while editing.
///
/// `isFocused` reads and writes first-responder state. `onSubmit` fires on
/// Return, `onCancel` on Escape; neither key inserts a newline.
struct SpellCheckedTextField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String = ""
    var textStyle: Font.TextStyle = .body
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    @Environment(\.zillaFontScale) private var fontScale
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        #if os(macOS)
        SpellCheckedFieldRepresentable(
            text: $text,
            isFocused: $isFocused,
            placeholder: placeholder,
            fontSize: textStyle.zillaBaseSize * fontScale,
            isEnabled: isEnabled,
            onSubmit: onSubmit,
            onCancel: onCancel
        )
        #else
        FocusBridgedTextField(
            text: $text,
            isFocused: $isFocused,
            placeholder: placeholder,
            textStyle: textStyle,
            onSubmit: onSubmit
        )
        #endif
    }
}

#if os(macOS)

final class SpellCheckingNSTextField: NSTextField {
    var wantsFocusWhenShown = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsFocusWhenShown, let window else { return }
        wantsFocusWhenShown = false
        DispatchQueue.main.async { window.makeFirstResponder(self) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.isContinuousSpellCheckingEnabled = true
        }
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        (notification.object as? NSTextView)?.isContinuousSpellCheckingEnabled = false
        super.textDidEndEditing(notification)
    }
}

private struct SpellCheckedFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let fontSize: CGFloat
    let isEnabled: Bool
    let onSubmit: (() -> Void)?
    let onCancel: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let field = SpellCheckingNSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: fontSize)
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.allowsEditingTextAttributes = false
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.font?.pointSize != fontSize {
            field.font = .systemFont(ofSize: fontSize)
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        field.isEnabled = isEnabled
        field.isEditable = isEnabled
        context.coordinator.syncFirstResponder(field, focused: isFocused)
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextField,
        context: Context
    ) -> CGSize? {
        guard let cell = nsView.cell else { return nil }
        let proposed = proposal.width ?? .infinity
        let unbounded = !(proposed > 0 && proposed.isFinite)
        let width = unbounded ? .greatestFiniteMagnitude : proposed
        let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        let fitted = cell.cellSize(forBounds: bounds)
        return CGSize(
            width: unbounded ? ceil(fitted.width) : width,
            height: ceil(fitted.height)
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SpellCheckedFieldRepresentable
        private var isSyncingFocus = false

        init(_ parent: SpellCheckedFieldRepresentable) {
            self.parent = parent
        }

        func syncFirstResponder(_ field: NSTextField, focused: Bool) {
            guard let window = field.window else {
                (field as? SpellCheckingNSTextField)?.wantsFocusWhenShown = focused
                return
            }
            let editing = (window.firstResponder as? NSTextView)?.delegate === field
                || window.firstResponder === field
            guard focused != editing else { return }
            isSyncingFocus = true
            if focused {
                window.makeFirstResponder(field)
            } else {
                window.makeFirstResponder(nil)
            }
            isSyncingFocus = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            report(focused: true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            report(focused: false)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel?()
                return true
            default:
                return false
            }
        }

        private func report(focused: Bool) {
            guard !isSyncingFocus, parent.isFocused != focused else { return }
            parent.isFocused = focused
        }
    }
}

#else

private struct FocusBridgedTextField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let textStyle: Font.TextStyle
    let onSubmit: (() -> Void)?

    @FocusState private var fieldFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .scaledFont(textStyle)
            .focused($fieldFocused)
            .onSubmit { onSubmit?() }
            .onAppear { fieldFocused = isFocused }
            .onChange(of: isFocused) { _, wanted in
                if fieldFocused != wanted { fieldFocused = wanted }
            }
            .onChange(of: fieldFocused) { _, focused in
                if isFocused != focused { isFocused = focused }
            }
    }
}

#endif
