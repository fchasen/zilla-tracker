#if canImport(AppKit) && os(macOS)
import AppKit
import SwiftUI
import MarginaliaSyntax
import MarginaliaRendering

/// macOS `NSViewRepresentable` that hosts an `NSTextView` configured against
/// an `EditorController`. The controller owns the storage; this view just
/// embeds a text view that points at the controller's content storage and
/// keeps the SwiftUI bindings in sync.
///
/// The `sizing` parameter controls whether the view grows to fit its
/// content (`.fitsContent`, the default) or fills the parent and scrolls
/// internally (`.fillContainer`).
public struct MarginaliaTextViewMac: NSViewRepresentable {
    @Binding public var text: String
    @Binding public var selection: NSRange
    public let controller: EditorController
    public let sizing: EditorSizing
    public let minHeight: CGFloat
    public let contextMenuItems: [MarginaliaContextMenuItem]

    public init(
        controller: EditorController,
        text: Binding<String>,
        selection: Binding<NSRange>,
        sizing: EditorSizing = .fitsContent,
        minHeight: CGFloat = 96,
        contextMenuItems: [MarginaliaContextMenuItem] = []
    ) {
        self.controller = controller
        self._text = text
        self._selection = selection
        self.sizing = sizing
        self.minHeight = minHeight
        self.contextMenuItems = contextMenuItems
    }

    public func makeNSView(context: Context) -> NSView {
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
        textView.drawsBackground = false
        textView.font = controller.theme.bodyFont
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.textView = textView
        controller.hostTextView = textView

        switch sizing {
        case .fitsContent:
            // No NSScrollView — the text view's intrinsic content size
            // drives SwiftUI layout, so the editor grows with content and
            // any surrounding ScrollView (or scroll-enabled parent) handles
            // overflow.
            textView.autoresizingMask = [.width]
            textView.usesFindBar = false
            textView.fitsContent = true
            textView.minimumIntrinsicHeight = minHeight
            controller.intrinsicSizeInvalidator = { [weak textView] in
                textView?.invalidateIntrinsicContentSize()
            }
            return textView
        case .fillContainer:
            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false
            textView.autoresizingMask = [.width]
            textView.usesFindBar = true
            scrollView.documentView = textView
            return scrollView
        }
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = textView(in: nsView) else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        if let mtv = textView as? MarginaliaNSTextView,
           mtv.minimumIntrinsicHeight != minHeight {
            mtv.minimumIntrinsicHeight = minHeight
        }
        coordinator.apply(text: text, selection: selection, to: textView)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard sizing == .fitsContent, let textView = textView(in: nsView) else { return nil }
        if let proposedWidth = proposal.width, proposedWidth > 0 {
            // Drive the text container's width so wrapping reflects the
            // SwiftUI parent's available width — otherwise the text view
            // sticks to whatever container size it was inited with.
            let inset = textView.textContainerInset
            let containerWidth = max(0, proposedWidth - inset.width * 2)
            controller.textContainer.size = NSSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        let intrinsic = textView.intrinsicContentSize
        let width = proposal.width ?? intrinsic.width
        return CGSize(width: width, height: max(intrinsic.height, 28))
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func textView(in nsView: NSView) -> NSTextView? {
        if let tv = nsView as? NSTextView { return tv }
        if let scroll = nsView as? NSScrollView { return scroll.documentView as? NSTextView }
        return nil
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarginaliaTextViewMac
        weak var textView: NSTextView?
        var lastAppliedText: String
        var lastAppliedSelection: NSRange
        var isApplyingFromBinding = false

        init(_ parent: MarginaliaTextViewMac) {
            self.parent = parent
            self.lastAppliedText = parent.text
            self.lastAppliedSelection = parent.selection
        }

        /// Pushes the SwiftUI bindings into the text view *only when they have
        /// changed externally*. The lastApplied watermarks are the bindings'
        /// values as of the last apply; they are NEVER updated from delegate
        /// callbacks. That's how we tell "external write" apart from "user
        /// just typed and the binding hasn't caught up yet" (or, in the
        /// `.constant` case, will never catch up).
        public func apply(text: String, selection: NSRange, to textView: NSTextView) {
            isApplyingFromBinding = true
            defer { isApplyingFromBinding = false }

            if text != lastAppliedText {
                if parent.controller.text != text {
                    parent.controller.setText(text)
                }
                lastAppliedText = text
            }

            if selection != lastAppliedSelection {
                // The binding's selection is in source coordinates (the
                // canonical text the host owns). Translate to display before
                // pushing onto the text view, which lives in display coords.
                let displayRange = parent.controller.displayMapping.displayRange(forSource: selection)
                let length = parent.controller.textStorage.length
                let location = max(0, min(displayRange.location, length))
                let remaining = max(0, length - location)
                let clamped = NSRange(
                    location: location,
                    length: max(0, min(displayRange.length, remaining))
                )
                if textView.selectedRange() != clamped {
                    textView.setSelectedRange(clamped)
                }
                lastAppliedSelection = selection
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard !isApplyingFromBinding else { return }
            // The text view edits the display storage; the controller's
            // storage observer mirrors the change back to source. Read from
            // the controller (source of truth) so the binding holds source,
            // not the elided WYSIWYG display.
            let newString = parent.controller.text
            if parent.text != newString {
                parent.text = newString
            }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingFromBinding else { return }
            guard let tv = notification.object as? NSTextView else { return }
            // Translate the text view's display-coord selection back to
            // source so the host's binding stays in source coordinates.
            let sourceRange = parent.controller.displayMapping
                .sourceRange(forDisplay: tv.selectedRange())
            parent.controller.selection = sourceRange
            if parent.selection != sourceRange {
                parent.selection = sourceRange
            }
        }

        public func textView(_ view: NSTextView,
                             menu: NSMenu,
                             for event: NSEvent,
                             at charIndex: Int) -> NSMenu? {
            guard !parent.contextMenuItems.isEmpty else { return menu }
            menu.addItem(NSMenuItem.separator())
            for item in parent.contextMenuItems {
                let menuItem = NSMenuItem(
                    title: item.title,
                    action: #selector(invokeContextMenuItem(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.state = item.isOn ? .on : .off
                if let symbol = item.systemImage {
                    menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
                menuItem.representedObject = ContextMenuActionBox(item.action)
                menu.addItem(menuItem)
            }
            return menu
        }

        @objc private func invokeContextMenuItem(_ sender: NSMenuItem) {
            (sender.representedObject as? ContextMenuActionBox)?.action()
        }

        public func textView(_ textView: NSTextView,
                             doCommandBy commandSelector: Selector) -> Bool {
            // ListContinuation / EditingOps operate on the canonical source
            // string and source-coord positions; translate the text view's
            // display-coord selection through the mapping before calling them.
            let mapping = parent.controller.displayMapping
            let sourceText = parent.controller.text
            let displayRange = textView.selectedRange()
            let sourceRange = mapping.sourceRange(forDisplay: displayRange)

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if displayRange.length == 0,
                   let result = ListContinuation.handleReturn(in: sourceText, cursor: sourceRange.location) {
                    apply(editResult: result, in: textView)
                    return true
                }
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if displayRange.length == 0,
                   let result = EditingOps.clearEmptyLineMarker(in: sourceText, cursor: sourceRange.location) {
                    apply(editResult: result, in: textView)
                    return true
                }
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)),
               let result = EditingOps.indentListLines(
                in: sourceText,
                selection: sourceRange
               ) {
                apply(editResult: result, in: textView)
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)),
               let result = EditingOps.outdentListLines(
                in: sourceText,
                selection: sourceRange
               ) {
                apply(editResult: result, in: textView)
                return true
            }
            return false
        }

        /// Replace the storage with `editResult.text` and put the cursor at
        /// `editResult.selection`, then update the bindings + watermarks so
        /// the next SwiftUI re-render is a no-op.
        ///
        /// Delegates to `EditorController.applyEdit(_:)` so clamping happens
        /// before `recomputeHidden` reads `controller.selection` — that
        /// ordering is what prevents `NSRangeException` when the
        /// edit-op result's selection points past the new shorter text
        /// (e.g. Shift-Tab outdent moving a sub-item to top level).
        private func apply(editResult result: EditResult, in textView: NSTextView) {
            isApplyingFromBinding = true
            parent.controller.applyEdit(result)
            isApplyingFromBinding = false
            parent.text = parent.controller.text
            parent.selection = parent.controller.selection
            // Pin watermarks to the bindings' actual values after the write.
            // With a `.constant` binding the write was a no-op, so the read
            // returns the pre-existing value — and that's what we record so
            // the next stale-binding re-render is a no-op skip.
            lastAppliedText = parent.text
            lastAppliedSelection = parent.selection
        }
    }
}

/// Reference wrapper for a `() -> Void` closure so it can ride along on
/// `NSMenuItem.representedObject` (which requires an Objective-C class).
private final class ContextMenuActionBox {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

/// `NSTextView` subclass that reports its content height as
/// `intrinsicContentSize` when `fitsContent` is enabled. SwiftUI uses that
/// to size the representable so the editor grows with content (no internal
/// scrolling). Width is left as `noIntrinsicMetric` so the SwiftUI parent
/// continues to own horizontal layout.
final class MarginaliaNSTextView: NSTextView {
    var fitsContent: Bool = false {
        didSet { invalidateIntrinsicContentSize() }
    }
    /// Floor for the intrinsic height in `fitsContent` mode — the editor
    /// starts at this height even when empty, then grows as content
    /// exceeds it.
    var minimumIntrinsicHeight: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        guard fitsContent else { return super.intrinsicContentSize }
        guard let layoutManager = textLayoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let used = layoutManager.usageBoundsForTextContainer
        let inset = textContainerInset
        let contentHeight = used.height + inset.height * 2
        // Floor at the larger of the user's configured min height and one
        // line of font height — so an empty editor is still tap-targetable.
        let floor = max(minimumIntrinsicHeight, font?.boundingRectForFont.height ?? 16)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(contentHeight, floor))
    }

    override func didChangeText() {
        super.didChangeText()
        if fitsContent { invalidateIntrinsicContentSize() }
    }
}
#endif
