import SwiftUI
import FolioHighlight
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct CodeEditorRepresentable: View {
    @Binding var text: String
    let language: CodeLanguage
    let theme: HighlightTheme
    let font: PlatformFont
    let fitsContent: Bool
    let minHeight: CGFloat
    let onLayoutManagerReady: (NSTextLayoutManager) -> Void

    public init(
        text: Binding<String>,
        language: CodeLanguage,
        theme: HighlightTheme,
        font: PlatformFont,
        fitsContent: Bool = false,
        minHeight: CGFloat = 0,
        onLayoutManagerReady: @escaping (NSTextLayoutManager) -> Void = { _ in }
    ) {
        self._text = text
        self.language = language
        self.theme = theme
        self.font = font
        self.fitsContent = fitsContent
        self.minHeight = minHeight
        self.onLayoutManagerReady = onLayoutManagerReady
    }

    public var body: some View {
        #if os(macOS)
        MacRepresentable(
            text: $text,
            language: language,
            theme: theme,
            font: font,
            fitsContent: fitsContent,
            minHeight: minHeight,
            onLayoutManagerReady: onLayoutManagerReady
        )
        #elseif canImport(UIKit)
        IOSRepresentable(
            text: $text,
            language: language,
            theme: theme,
            font: font,
            fitsContent: fitsContent,
            minHeight: minHeight,
            onLayoutManagerReady: onLayoutManagerReady
        )
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)

private struct MacRepresentable: NSViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    let theme: HighlightTheme
    let font: PlatformFont
    let fitsContent: Bool
    let minHeight: CGFloat
    let onLayoutManagerReady: (NSTextLayoutManager) -> Void

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(language: language, theme: theme, font: font)
    }

    func makeNSView(context: Context) -> NSView {
        let textView = IntrinsicCodeNSTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = font
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.fitsContent = fitsContent
        textView.minimumIntrinsicHeight = minHeight

        if let storage = textView.textContentStorage?.textStorage {
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            context.coordinator.highlighter.applyInitialAttributes(
                to: storage,
                text: text,
                language: language,
                font: font
            )
            context.coordinator.observe(storage: storage)
        }

        context.coordinator.lastAppliedText = text
        context.coordinator.textView = textView
        context.coordinator.propagateText = { [text = self.$text] newText in
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }
        }
        context.coordinator.invalidateIntrinsic = { [weak textView] in
            textView?.invalidateIntrinsicContentSize()
        }
        if let layoutManager = textView.textLayoutManager {
            onLayoutManagerReady(layoutManager)
        }
        return textView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = nsView as? IntrinsicCodeNSTextView else { return }
        context.coordinator.theme = theme
        context.coordinator.font = font
        context.coordinator.language = language
        if textView.font != font {
            textView.font = font
        }
        if textView.fitsContent != fitsContent {
            textView.fitsContent = fitsContent
        }
        if textView.minimumIntrinsicHeight != minHeight {
            textView.minimumIntrinsicHeight = minHeight
        }
        context.coordinator.propagateText = { [text = self.$text] newText in
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }
        }
        context.coordinator.invalidateIntrinsic = { [weak textView] in
            textView?.invalidateIntrinsicContentSize()
        }
        if text != context.coordinator.lastAppliedText {
            context.coordinator.applyExternalText(text, to: textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard fitsContent, let textView = nsView as? NSTextView else { return nil }
        if let proposedWidth = proposal.width, proposedWidth > 0 {
            let inset = textView.textContainerInset
            let containerWidth = max(0, proposedWidth - inset.width * 2)
            textView.textContainer?.size = NSSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        let intrinsic = textView.intrinsicContentSize
        let width = proposal.width ?? intrinsic.width
        return CGSize(width: width, height: max(intrinsic.height, minHeight))
    }
}

final class IntrinsicCodeNSTextView: NSTextView {
    var fitsContent: Bool = false {
        didSet { invalidateIntrinsicContentSize() }
    }
    var minimumIntrinsicHeight: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        guard fitsContent else { return super.intrinsicContentSize }
        guard let layoutManager = textLayoutManager else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let used = layoutManager.usageBoundsForTextContainer
        let inset = textContainerInset
        let contentHeight = used.height + inset.height * 2
        let floor = max(minimumIntrinsicHeight, font?.boundingRectForFont.height ?? 16)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(contentHeight, floor))
    }

    override func didChangeText() {
        super.didChangeText()
        if fitsContent { invalidateIntrinsicContentSize() }
    }
}

#elseif canImport(UIKit)

/// `UITextView` doesn't expose `textContentStorage` directly even when
/// constructed with `usingTextLayoutManager: true`. The `NSTextContentStorage`
/// is reachable via the layout manager's content manager — that's the
/// supported path on iOS.
@MainActor
private func uiTextStorage(_ textView: UITextView) -> NSTextStorage? {
    (textView.textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
}

private struct IOSRepresentable: UIViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    let theme: HighlightTheme
    let font: PlatformFont
    let fitsContent: Bool
    let minHeight: CGFloat
    let onLayoutManagerReady: (NSTextLayoutManager) -> Void

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(language: language, theme: theme, font: font)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.textContainer.widthTracksTextView = true
        textView.isScrollEnabled = !fitsContent

        if let storage = uiTextStorage(textView) {
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            context.coordinator.highlighter.applyInitialAttributes(
                to: storage,
                text: text,
                language: language,
                font: font
            )
            context.coordinator.observe(storage: storage)
        }

        context.coordinator.lastAppliedText = text
        context.coordinator.textView = textView
        context.coordinator.propagateText = { [text = self.$text] newText in
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }
        }
        context.coordinator.invalidateIntrinsic = { [weak textView] in
            textView?.invalidateIntrinsicContentSize()
        }
        if let layoutManager = textView.textLayoutManager {
            onLayoutManagerReady(layoutManager)
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.theme = theme
        context.coordinator.font = font
        context.coordinator.language = language
        if textView.font != font {
            textView.font = font
        }
        if textView.isScrollEnabled == fitsContent {
            textView.isScrollEnabled = !fitsContent
        }
        context.coordinator.propagateText = { [text = self.$text] newText in
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }
        }
        context.coordinator.invalidateIntrinsic = { [weak textView] in
            textView?.invalidateIntrinsicContentSize()
        }
        if text != context.coordinator.lastAppliedText {
            context.coordinator.applyExternalText(text, to: textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard fitsContent else { return nil }
        if let proposedWidth = proposal.width, proposedWidth > 0 {
            let inset = uiView.textContainerInset
            let containerWidth = max(0, proposedWidth - inset.left - inset.right)
            uiView.textContainer.size = CGSize(
                width: containerWidth,
                height: .greatestFiniteMagnitude
            )
        }
        let intrinsic = uiView.intrinsicContentSize
        let width = proposal.width ?? intrinsic.width
        return CGSize(width: width, height: max(intrinsic.height, minHeight))
    }
}
#endif

#if os(macOS) || canImport(UIKit)

@MainActor
final class EditorCoordinator: NSObject {
    let highlighter: FolioHighlighter
    var language: CodeLanguage
    var font: PlatformFont
    var theme: HighlightTheme {
        didSet { highlighter.theme = theme }
    }
    var lastAppliedText: String = ""
    var propagateText: (String) -> Void = { _ in }
    var invalidateIntrinsic: () -> Void = {}

    private var isApplyingExternal: Bool = false
    private weak var observedStorage: NSTextStorage?

    #if os(macOS)
    weak var textView: NSTextView?
    #else
    weak var textView: UITextView?
    #endif

    init(language: CodeLanguage, theme: HighlightTheme, font: PlatformFont) {
        self.language = language
        self.theme = theme
        self.font = font
        self.highlighter = FolioHighlighter(theme: theme)
        super.init()
    }

    func observe(storage: NSTextStorage) {
        observedStorage = storage
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: storage
        )
    }

    deinit {
        if let observedStorage {
            NotificationCenter.default.removeObserver(
                self,
                name: NSTextStorage.didProcessEditingNotification,
                object: observedStorage
            )
        }
    }

    @objc private func storageDidProcessEditing(_ notification: Notification) {
        MainActor.assumeIsolated {
            handleStorageEdit(notification: notification)
        }
    }

    private func handleStorageEdit(notification: Notification) {
        guard !isApplyingExternal,
              let storage = notification.object as? NSTextStorage else { return }
        let editedMask = storage.editedMask
        guard editedMask.contains(.editedCharacters) else { return }
        let editedRange = storage.editedRange
        let changeInLength = storage.changeInLength
        let oldLength = max(0, editedRange.length - changeInLength)
        let replacedRange = NSRange(location: editedRange.location, length: oldLength)
        let nsText = storage.string as NSString
        let replacement = nsText.substring(with: editedRange)
        let newText = storage.string

        let edit = highlighter.didEdit(
            replacedRange: replacedRange,
            replacement: replacement,
            in: newText
        )
        highlighter.applyEditAttributes(to: storage, edit: edit, font: font)
        lastAppliedText = newText
        propagateText(newText)
        invalidateIntrinsic()
    }

    #if os(macOS)
    func applyExternalText(_ text: String, to textView: NSTextView) {
        guard let storage = textView.textContentStorage?.textStorage else { return }
        applyExternal(text: text, to: storage)
    }
    #else
    func applyExternalText(_ text: String, to textView: UITextView) {
        guard let storage = uiTextStorage(textView) else { return }
        applyExternal(text: text, to: storage)
    }
    #endif

    private func applyExternal(text: String, to storage: NSTextStorage) {
        isApplyingExternal = true
        defer { isApplyingExternal = false }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.replaceCharacters(in: fullRange, with: text)
        highlighter.applyInitialAttributes(
            to: storage,
            text: text,
            language: language,
            font: font
        )
        lastAppliedText = text
        invalidateIntrinsic()
    }
}

#if os(macOS)
extension EditorCoordinator: NSTextViewDelegate {}
#else
extension EditorCoordinator: UITextViewDelegate {}
#endif

#endif
