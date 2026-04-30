#if canImport(AppKit) && os(macOS)
import AppKit
import SwiftUI
import MarginaliaSyntax
import MarginaliaRendering

/// macOS `NSViewRepresentable` that hosts an `NSTextView` configured against
/// an `EditorController`. The controller owns the storage; this view just
/// embeds a text view that points at the controller's content storage and
/// keeps the SwiftUI bindings in sync.
public struct MarginaliaTextViewMac: NSViewRepresentable {
    @Binding public var text: String
    @Binding public var selection: NSRange
    public let controller: EditorController

    public init(controller: EditorController, text: Binding<String>, selection: Binding<NSRange>) {
        self.controller = controller
        self._text = text
        self._selection = selection
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = MarginaliaNSTextView(
            frame: .zero,
            textContainer: controller.textContainer
        )
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.font = controller.theme.bodyFont
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            controller.setText(text)
        }
        let storageLength = controller.textStorage.length
        let clampedSelection = NSRange(
            location: max(0, min(selection.location, storageLength)),
            length: max(0, min(selection.length, storageLength - max(0, min(selection.location, storageLength))))
        )
        if textView.selectedRange() != clampedSelection {
            textView.setSelectedRange(clampedSelection)
        }
        controller.selection = clampedSelection
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarginaliaTextViewMac
        weak var textView: NSTextView?

        init(_ parent: MarginaliaTextViewMac) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newString = tv.string
            DispatchQueue.main.async {
                if self.parent.text != newString {
                    self.parent.text = newString
                }
            }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let r = tv.selectedRange()
            DispatchQueue.main.async {
                if self.parent.selection != r {
                    self.parent.selection = r
                }
                self.parent.controller.selection = r
            }
        }

        public func textView(_ textView: NSTextView,
                             doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let range = textView.selectedRange()
                if range.length == 0,
                   let result = ListContinuation.handleReturn(in: textView.string, cursor: range.location) {
                    parent.controller.setText(result.text)
                    parent.text = result.text
                    parent.controller.selection = result.selection
                    parent.selection = result.selection
                    return true
                }
            }
            return false
        }
    }
}

/// `NSTextView` subclass — currently just a marker so we can override
/// behavior later (e.g. multi-cursor key bindings) without touching the
/// representable wrapper.
final class MarginaliaNSTextView: NSTextView {}
#endif
