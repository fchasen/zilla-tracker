#if canImport(UIKit)
import UIKit
import SwiftUI
import MarginaliaSyntax
import MarginaliaRendering

/// iOS `UIViewRepresentable` that hosts a TextKit-2 `UITextView` configured
/// against the same `EditorController` the macOS path uses.
public struct MarginaliaTextViewIOS: UIViewRepresentable {
    @Binding public var text: String
    @Binding public var selection: NSRange
    public let controller: EditorController

    public init(controller: EditorController, text: Binding<String>, selection: Binding<NSRange>) {
        self.controller = controller
        self._text = text
        self._selection = selection
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = MarginaliaUITextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.font = controller.theme.bodyFont
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocorrectionType = .default
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.adjustsFontForContentSizeCategory = true
        textView.text = controller.textStorage.string
        if #available(iOS 16.0, *) {
            textView.findInteractionEnabled = true
        }
        // Wire the controller's storage as the text view's storage. UITextView
        // doesn't expose a designated init for an existing layout manager, so
        // we mirror the controller's text into the view's own storage and
        // re-apply attributes on each refresh.
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            controller.setText(text)
        }
        let storageLength = (text as NSString).length
        let clamped = NSRange(
            location: max(0, min(selection.location, storageLength)),
            length: max(0, min(selection.length, storageLength - max(0, min(selection.location, storageLength))))
        )
        if uiView.selectedRange != clamped {
            uiView.selectedRange = clamped
        }
        controller.selection = clamped
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarginaliaTextViewIOS
        init(_ parent: MarginaliaTextViewIOS) { self.parent = parent }

        public func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            let r = textView.selectedRange
            if parent.selection != r {
                parent.selection = r
            }
            parent.controller.selection = r
        }

        public func textView(_ textView: UITextView,
                             shouldChangeTextIn range: NSRange,
                             replacementText text: String) -> Bool {
            if text == "\n",
               let result = ListContinuation.handleReturn(
                in: textView.text,
                cursor: range.location
               ) {
                textView.text = result.text
                textView.selectedRange = result.selection
                parent.text = result.text
                parent.selection = result.selection
                parent.controller.setText(result.text)
                return false
            }
            return true
        }
    }
}

final class MarginaliaUITextView: UITextView {}
#endif
