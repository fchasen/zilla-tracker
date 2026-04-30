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
    public let sizing: EditorSizing
    public let minHeight: CGFloat

    public init(
        controller: EditorController,
        text: Binding<String>,
        selection: Binding<NSRange>,
        sizing: EditorSizing = .fitsContent,
        minHeight: CGFloat = 96
    ) {
        self.controller = controller
        self._text = text
        self._selection = selection
        self.sizing = sizing
        self.minHeight = minHeight
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
        textView.isScrollEnabled = (sizing == .fillContainer)
        if #available(iOS 16.0, *) {
            textView.findInteractionEnabled = (sizing == .fillContainer)
        }
        context.coordinator.textView = textView
        controller.hostTextView = textView
        if sizing == .fitsContent {
            controller.intrinsicSizeInvalidator = { [weak textView] in
                textView?.invalidateIntrinsicContentSize()
            }
        }
        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.apply(text: text, selection: selection, to: uiView)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard sizing == .fitsContent else { return nil }
        if let proposedWidth = proposal.width, proposedWidth > 0 {
            let inset = uiView.textContainerInset
            controller.textContainer.size = CGSize(
                width: max(0, proposedWidth - inset.left - inset.right),
                height: .greatestFiniteMagnitude
            )
        }
        let intrinsic = uiView.intrinsicContentSize
        let width = proposal.width ?? intrinsic.width
        return CGSize(width: width, height: max(intrinsic.height, minHeight))
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarginaliaTextViewIOS
        weak var textView: UITextView?
        var lastAppliedText: String
        var lastAppliedSelection: NSRange
        var isApplyingFromBinding = false

        init(_ parent: MarginaliaTextViewIOS) {
            self.parent = parent
            self.lastAppliedText = parent.text
            self.lastAppliedSelection = parent.selection
        }

        /// See `MarginaliaTextViewMac.Coordinator.apply` for the rationale.
        /// Same logic, different platform types.
        public func apply(text: String, selection: NSRange, to textView: UITextView) {
            isApplyingFromBinding = true
            defer { isApplyingFromBinding = false }

            if text != lastAppliedText {
                if parent.controller.textStorage.string != text {
                    parent.controller.setText(text)
                }
                lastAppliedText = text
            }

            if selection != lastAppliedSelection {
                let length = parent.controller.textStorage.length
                let location = max(0, min(selection.location, length))
                let remaining = max(0, length - location)
                let clamped = NSRange(
                    location: location,
                    length: max(0, min(selection.length, remaining))
                )
                if textView.selectedRange != clamped {
                    textView.selectedRange = clamped
                }
                lastAppliedSelection = selection
            }
        }

        public func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingFromBinding else { return }
            let newText = textView.text ?? ""
            if parent.text != newText {
                parent.text = newText
            }
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingFromBinding else { return }
            let r = textView.selectedRange
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
                isApplyingFromBinding = true
                // Delegate to controller.applyEdit so the selection is
                // clamped BEFORE the synchronous refresh reads it — same
                // crash-prevention ordering the macOS coordinator uses.
                parent.controller.applyEdit(result)
                isApplyingFromBinding = false
                parent.text = parent.controller.text
                parent.selection = parent.controller.selection
                lastAppliedText = parent.text
                lastAppliedSelection = parent.selection
                return false
            }
            return true
        }
    }
}

final class MarginaliaUITextView: UITextView {}
#endif
