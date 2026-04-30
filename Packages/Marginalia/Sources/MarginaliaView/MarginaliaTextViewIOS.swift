#if canImport(UIKit)
import UIKit
import SwiftUI
import MarginaliaSyntax
import MarginaliaRendering

/// iOS `UIViewRepresentable` that hosts a TextKit-2 `UITextView` configured
/// against the same `EditorController` the macOS path uses. The text view is
/// initialized with the controller's `NSTextContainer` so it shares the
/// controller's TK2 stack — that way attribute updates the controller pushes
/// into its `NSTextStorage` are automatically reflected in the view.
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
        // `init(frame:textContainer:)` is the designated init; UITextView uses
        // TextKit 2 when the container's `textLayoutManager` is non-nil, which
        // it is here because the controller wired the container into its
        // `NSTextLayoutManager`.
        let textView = MarginaliaUITextView(frame: .zero, textContainer: controller.textContainer)
        textView.delegate = context.coordinator
        textView.font = controller.theme.bodyFont
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocorrectionType = .default
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.adjustsFontForContentSizeCategory = true
        if #available(iOS 16.0, *) {
            textView.findInteractionEnabled = true
        }
        context.coordinator.textView = textView
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if text != coordinator.lastObservedText {
            if controller.textStorage.string != text {
                controller.setText(text)
            }
            coordinator.lastObservedText = text
        }

        if selection != coordinator.lastObservedSelection {
            let clamped = clamp(selection, to: controller.textStorage.length)
            if uiView.selectedRange != clamped {
                uiView.selectedRange = clamped
            }
            coordinator.lastObservedSelection = selection
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let remaining = max(0, length - location)
        return NSRange(location: location, length: max(0, min(range.length, remaining)))
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarginaliaTextViewIOS
        weak var textView: UITextView?
        var lastObservedText: String
        var lastObservedSelection: NSRange

        init(_ parent: MarginaliaTextViewIOS) {
            self.parent = parent
            self.lastObservedText = parent.text
            self.lastObservedSelection = parent.selection
        }

        public func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            lastObservedText = newText
            if parent.text != newText {
                parent.text = newText
            }
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            let r = textView.selectedRange
            lastObservedSelection = r
            parent.controller.selection = r
            if parent.selection != r {
                parent.selection = r
            }
        }

        public func textView(_ textView: UITextView,
                             shouldChangeTextIn range: NSRange,
                             replacementText text: String) -> Bool {
            if text == "\n",
               let result = ListContinuation.handleReturn(
                in: textView.text ?? "",
                cursor: range.location
               ) {
                parent.controller.setText(result.text)
                textView.selectedRange = result.selection
                lastObservedText = result.text
                lastObservedSelection = result.selection
                parent.controller.selection = result.selection
                parent.text = result.text
                parent.selection = result.selection
                return false
            }
            return true
        }
    }
}

final class MarginaliaUITextView: UITextView {}
#endif
