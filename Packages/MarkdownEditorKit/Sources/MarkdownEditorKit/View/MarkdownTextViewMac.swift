#if canImport(AppKit) && os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct MarkdownTextViewMac: NSViewRepresentable {
    @Binding public var text: String
    public let controller: MarkdownEditorController
    public let sizing: EditorSizing
    public let minHeight: CGFloat
    public let contextMenuItems: [EditorContextMenuItem]
    public let spellChecking: MarkdownSpellChecking
    public let isEditable: Bool
    public let onSubmit: (() -> Void)?

    public init(
        controller: MarkdownEditorController,
        text: Binding<String>,
        sizing: EditorSizing = .fitsContent,
        minHeight: CGFloat = 96,
        contextMenuItems: [EditorContextMenuItem] = [],
        spellChecking: MarkdownSpellChecking = .full,
        isEditable: Bool = true,
        onSubmit: (() -> Void)? = nil
    ) {
        self.controller = controller
        self._text = text
        self.sizing = sizing
        self.minHeight = minHeight
        self.contextMenuItems = contextMenuItems
        self.spellChecking = spellChecking
        self.isEditable = isEditable
        self.onSubmit = onSubmit
    }

    public func makeNSView(context: Context) -> NSView {
        let textView = MarkdownNSTextView(frame: .zero, textContainer: controller.textContainer)
        textView.delegate = context.coordinator
        textView.applyEditorDefaults()
        textView.isEditable = isEditable
        controller.isEditable = isEditable
        applySpellChecking(spellChecking, to: textView)
        textView.drawsBackground = false
        textView.textContainerInset = controller.theme.textContainerInset
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.textView = textView
        controller.hostTextView = textView
        textView.markdownController = controller
        textView.onSubmit = onSubmit
        controller.textSink = { [weak coordinator = context.coordinator] markdown in
            coordinator?.push(markdown)
        }

        let press = NSPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePluginLongPress(_:))
        )
        press.minimumPressDuration = 0.5
        press.delegate = context.coordinator
        textView.addGestureRecognizer(press)

        switch sizing {
        case .fitsContent:
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
            scrollView.automaticallyAdjustsContentInsets = true
            textView.autoresizingMask = [.width]
            textView.usesFindBar = true
            scrollView.documentView = textView
            return scrollView
        }
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = textView(in: nsView) else { return }
        context.coordinator.parent = self
        if let mtv = textView as? MarkdownNSTextView {
            if mtv.minimumIntrinsicHeight != minHeight {
                mtv.minimumIntrinsicHeight = minHeight
            }
            mtv.updateCodeBlockBgLayerFill()
            mtv.onSubmit = onSubmit
        }
        let inset = controller.theme.textContainerInset
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
        }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        controller.isEditable = isEditable
        applySpellChecking(spellChecking, to: textView)
        controller.applyExternalText(text)
    }

    private func applySpellChecking(_ mode: MarkdownSpellChecking, to textView: NSTextView) {
        if textView.isContinuousSpellCheckingEnabled != mode.spellingEnabled {
            textView.isContinuousSpellCheckingEnabled = mode.spellingEnabled
        }
        if textView.isGrammarCheckingEnabled != mode.grammarEnabled {
            textView.isGrammarCheckingEnabled = mode.grammarEnabled
        }
        if textView.isAutomaticSpellingCorrectionEnabled != mode.autocorrectEnabled {
            textView.isAutomaticSpellingCorrectionEnabled = mode.autocorrectEnabled
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard sizing == .fitsContent, let textView = textView(in: nsView) else { return nil }
        if let proposedWidth = proposal.width, proposedWidth > 0 {
            let inset = textView.textContainerInset
            let containerWidth = max(0, proposedWidth - inset.width * 2)
            if abs(controller.textContainer.size.width - containerWidth) > 0.5 {
                controller.textContainer.size = NSSize(
                    width: containerWidth,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
        }
        let intrinsic = textView.intrinsicContentSize
        let width = proposal.width ?? intrinsic.width
        return CGSize(width: width, height: max(intrinsic.height, 28))
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func textView(in nsView: NSView) -> NSTextView? {
        if let tv = nsView as? NSTextView { return tv }
        if let scroll = nsView as? NSScrollView { return scroll.documentView as? NSTextView }
        return nil
    }

    public final class Coordinator: NSObject, NSTextViewDelegate, NSGestureRecognizerDelegate {
        var parent: MarkdownTextViewMac
        weak var textView: NSTextView?

        init(_ parent: MarkdownTextViewMac) {
            self.parent = parent
            super.init()
        }

        func push(_ markdown: String) {
            if parent.text != markdown {
                parent.text = markdown
            }
        }

        @objc func handlePluginLongPress(_ gr: NSPressGestureRecognizer) {
            guard gr.state == .began,
                  let textView = textView as? MarkdownNSTextView,
                  let controller = textView.markdownController,
                  !controller.plugins.isEmpty else { return }
            let charIndex = textView.characterIndexForInsertion(at: gr.location(in: textView))
            for plugin in controller.plugins {
                if plugin.props.handleLongPress?(controller, charIndex) == true { return }
            }
        }

        public func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer
        ) -> Bool { true }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.controller.selectionDidChange(tv.selectedRange())
        }

        public func undoManager(for view: NSTextView) -> UndoManager? {
            parent.controller.undoManager
        }

        public func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            parent.controller.hostShouldChangeText(in: affectedCharRange, replacement: replacementString)
        }

        public func textView(
            _ textView: NSTextView,
            shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
            toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]
        ) -> [NSAttributedString.Key: Any] {
            parent.controller.adjustedTypingAttributes(newTypingAttributes)
        }

        public func textView(
            _ textView: NSTextView,
            writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange
        ) -> [NSValue] {
            parent.controller.writingToolsIgnoredRanges(in: enclosingRange).map { NSValue(range: $0) }
        }

        public func textViewWritingToolsWillBegin(_ textView: NSTextView) {
            parent.controller.writingToolsWillBegin()
        }

        public func textViewWritingToolsDidEnd(_ textView: NSTextView) {
            parent.controller.writingToolsDidEnd()
        }

        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let controller = parent.controller
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if controller.handleNewline() { return true }
            case #selector(NSResponder.deleteBackward(_:)):
                if controller.handleBackspace() { return true }
            case #selector(NSResponder.insertTab(_:)):
                if controller.handleTab(backward: false) { return true }
            case #selector(NSResponder.insertBacktab(_:)):
                if controller.handleTab(backward: true) { return true }
            default:
                break
            }
            return controller.handleCommand(commandSelector)
        }

        public func textView(
            _ textView: NSTextView,
            shouldCheckTextIn range: NSRange,
            offset: Int,
            types checkingTypes: UnsafeMutablePointer<NSTextCheckingTypes>
        ) -> NSRange {
            guard parent.spellChecking != .off else { return range }
            return MarkdownSpellChecking.firstCheckableRange(in: range, storage: parent.controller.textStorage)
        }

        public func textView(
            _ view: NSTextView,
            menu: NSMenu,
            for event: NSEvent,
            at charIndex: Int
        ) -> NSMenu? {
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
    }
}

private final class ContextMenuActionBox {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

final class MarkdownNSTextView: NSTextView {
    static let markdownType = NSPasteboard.PasteboardType(MarkdownEditorController.markdownPasteboardType)

    var fitsContent: Bool = false {
        didSet { invalidateIntrinsicContentSize() }
    }

    var minimumIntrinsicHeight: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    weak var markdownController: MarkdownEditorController?
    var onSubmit: (() -> Void)?
    private var isPastingPlainText = false

    func applyEditorDefaults() {
        isRichText = true
        importsGraphics = false
        usesFontPanel = false
        usesRuler = false
        isSelectable = true
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        smartInsertDeleteEnabled = false
        allowedWritingToolsResultOptions = [.plainText]
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [Self.markdownType, .rtfd, .rtf, .html, .string, .URL, .fileURL]
            + PastedImagePolicy.dataTypes.map { NSPasteboard.PasteboardType($0.identifier) }
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        readablePasteboardTypes
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.writablePasteboardTypes.filter { $0 != Self.markdownType }
        types.append(Self.markdownType)
        return types
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let controller = markdownController, type == .string || type == Self.markdownType else {
            return super.writeSelection(to: pboard, type: type)
        }
        let range = selectedRanges.map(\.rangeValue).reduce(nil as NSRange?) { partial, next in
            partial.map { NSUnionRange($0, next) } ?? next
        } ?? selectedRange()
        guard range.length > 0 else { return false }
        return pboard.setString(controller.markdownForCopy(range: range), forType: type)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        isPastingPlainText = true
        defer { isPastingPlainText = false }
        super.pasteAsPlainText(sender)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let controller = markdownController, controller.isEditable else {
            return super.readSelection(from: pboard, type: type)
        }
        let selection = rangeForUserTextChange
        guard selection.location != NSNotFound else { return false }
        let payload = pastePayload(from: pboard, type: type)
        let images = Self.pastedImages(from: pboard, forcePlain: isPastingPlainText)
        guard !payload.isEmpty || !images.isEmpty else { return false }
        let event = PasteEvent(
            text: payload.anyText,
            html: pboard.string(forType: .html),
            plainText: payload.forcePlain,
            source: .paste,
            selection: selection,
            inCode: controller.isLocationInCode(selection.location),
            images: images
        )
        for plugin in controller.plugins {
            if plugin.props.handlePaste?(controller, event) == true { return true }
        }
        guard !payload.isEmpty else { return false }
        return controller.paste(payload, replacing: selection)
    }

    override func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        if isEditable, markdownController?.isEditable == true, Self.carriesImages(dragInfo.draggingPasteboard) {
            return .copy
        }
        return super.dragOperation(for: dragInfo, type: type)
    }

    static func carriesImages(_ pboard: NSPasteboard) -> Bool {
        if pboard.types?.contains(markdownType) == true { return false }
        let imageFiles = pboard.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]
        ) ?? []
        if !imageFiles.isEmpty { return true }
        let dataTypes = PastedImagePolicy.dataTypes.map { NSPasteboard.PasteboardType($0.identifier) }
        guard pboard.availableType(from: dataTypes) != nil else { return false }
        let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty || PastedImagePolicy.isSingleURL(text)
    }

    static func pastedImages(from pboard: NSPasteboard, forcePlain: Bool) -> [PastedImage] {
        let fileURLs = pboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return PastedImagePolicy.images(
            hasMarkdown: pboard.types?.contains(markdownType) == true,
            forcePlain: forcePlain,
            plainText: pboard.string(forType: .string),
            fileURLs: fileURLs,
            dataImages: {
                (pboard.pasteboardItems ?? []).compactMap { item in
                    guard let type = PastedImagePolicy.preferredDataType(in: item.types.map(\.rawValue)),
                          let data = item.data(forType: NSPasteboard.PasteboardType(type.identifier)),
                          !data.isEmpty
                    else { return nil }
                    return PastedImage(data: data, contentType: type)
                }
            }
        )
    }

    private func pastePayload(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> PastePayload {
        let plain = pboard.string(forType: .string) ?? pboard.string(forType: .URL)
        if isPastingPlainText {
            return PastePayload(plainText: plain ?? pboard.string(forType: Self.markdownType), forcePlain: true)
        }
        if let markdown = pboard.string(forType: Self.markdownType) {
            return PastePayload(markdown: markdown, plainText: plain)
        }
        switch type {
        case .rtfd, .rtf, .html:
            let rich = Self.richText(from: pboard, type: type)
            return PastePayload(plainText: plain, richText: rich)
        default:
            return PastePayload(plainText: plain)
        }
    }

    private static func richText(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> NSAttributedString? {
        guard let data = pboard.data(forType: type) else { return nil }
        switch type {
        case .rtfd: return NSAttributedString(rtfd: data, documentAttributes: nil)
        case .rtf: return NSAttributedString(rtf: data, documentAttributes: nil)
        case .html: return NSAttributedString(html: data, documentAttributes: nil)
        default: return nil
        }
    }

    override func changeFont(_ sender: Any?) {
        guard let controller = markdownController, controller.isEditable else { return }
        let manager = (sender as? NSFontManager) ?? NSFontManager.shared
        for action in controller.fontTraitActions(converting: { manager.convert($0) }) {
            controller.perform(action)
        }
    }

    override func underline(_ sender: Any?) {}

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markdownController?.isSettingMarkedText = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        markdownController?.isSettingMarkedText = false
    }

    override func unmarkText() {
        super.unmarkText()
        markdownController?.pushBinding()
        markdownController?.refreshInlineContentIfNeeded()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        markdownController?.pushBinding()
    }

    override func mouseDown(with event: NSEvent) {
        if let controller = markdownController {
            let point = convert(event.locationInWindow, from: nil)
            let charIndex = characterIndexForInsertion(at: point)
            for plugin in controller.plugins {
                if plugin.props.handleClick?(controller, charIndex) == true { return }
            }
            if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
               let taskIndex = taskGutterIndex(at: point, charIndex: charIndex),
               controller.toggleTask(at: taskIndex) {
                return
            }
        }
        super.mouseDown(with: event)
    }

    func taskGutterIndex(at point: NSPoint, charIndex: Int) -> Int? {
        guard let controller = markdownController else { return nil }
        let info = controller.paragraphInfo(at: charIndex)
        guard !info.isTrailingEmpty, info.block.isListItemStart, info.block.task != nil,
              let rect = controller.rect(forCharacterAt: info.content.location) else { return nil }
        let gutter = NSRect(x: rect.minX - MarkdownTaskGutter.width, y: rect.minY, width: MarkdownTaskGutter.width, height: max(rect.height, 1))
        return gutter.contains(point) ? info.content.location : nil
    }

    override func keyDown(with event: NSEvent) {
        if let controller = markdownController,
           !controller.plugins.isEmpty,
           !hasMarkedText(),
           let key = pluginKeyName(for: event) {
            for plugin in controller.plugins {
                if plugin.props.handleKeyDown?(controller, key) == true { return }
            }
        }
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control),
           event.keyCode == 36 || event.keyCode == 76,
           !hasMarkedText(),
           markdownController?.exitCodeBlock() == true {
            return
        }
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control),
           !hasMarkedText(),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           let action = shortcutAction(forCommandKey: chars, shift: event.modifierFlags.contains(.shift)) {
            markdownController?.perform(action)
            return
        }
        if let onSubmit,
           event.keyCode == 36 || event.keyCode == 76,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control),
           !event.modifierFlags.contains(.option),
           !hasMarkedText() {
            if event.modifierFlags.contains(.shift) {
                doCommand(by: #selector(NSResponder.insertNewline(_:)))
            } else {
                onSubmit()
            }
            return
        }
        super.keyDown(with: event)
    }

    private func pluginKeyName(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case 53: return PluginKeyName.escape
        case 36, 76: return PluginKeyName.enter
        case 48: return PluginKeyName.tab
        case 126: return PluginKeyName.arrowUp
        case 125: return PluginKeyName.arrowDown
        case 123: return PluginKeyName.arrowLeft
        case 124: return PluginKeyName.arrowRight
        default: return nil
        }
    }

    private func shortcutAction(forCommandKey key: String, shift: Bool) -> EditorAction? {
        markdownController?.keymap.action(forKey: KeySpec.make(key: key, mod: true, shift: shift))
    }

    override var intrinsicContentSize: NSSize {
        guard fitsContent, let layoutManager = textLayoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let used = layoutManager.usageBoundsForTextContainer
        let contentHeight = used.height + textContainerInset.height * 2
        let floor = max(minimumIntrinsicHeight, font?.boundingRectForFont.height ?? 16)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(contentHeight, floor))
    }

    override func didChangeText() {
        super.didChangeText()
        if fitsContent { invalidateIntrinsicContentSize() }
        scheduleCodeBlockBgUpdate()
        markdownController?.flushDocumentChanges()
    }

    override func layout() {
        super.layout()
        codeBlockBgLayer.frame = bounds
        scheduleCodeBlockBgUpdate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ensureCodeBlockBgLayer()
        scheduleCodeBlockBgUpdate()
    }

    private let codeBlockBgLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.actions = ["path": NSNull(), "frame": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer.zPosition = -1
        return layer
    }()

    private var codeBlockBgLayerInstalled = false
    private var bgUpdateScheduled = false

    private func ensureCodeBlockBgLayer() {
        guard !codeBlockBgLayerInstalled else { return }
        wantsLayer = true
        guard let layer else { return }
        let fill = markdownController?.theme.codeBlock.fillColor ?? .codeBlockDefaultFill
        codeBlockBgLayer.fillColor = fill.cgColor
        codeBlockBgLayer.frame = layer.bounds
        layer.insertSublayer(codeBlockBgLayer, at: 0)
        codeBlockBgLayerInstalled = true
    }

    func updateCodeBlockBgLayerFill() {
        guard let controller = markdownController else { return }
        codeBlockBgLayer.fillColor = controller.theme.codeBlock.fillColor.cgColor
    }

    func scheduleCodeBlockBgUpdate() {
        guard !bgUpdateScheduled else { return }
        bgUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.bgUpdateScheduled = false
            self?.updateCodeBlockBgPath()
        }
    }

    private func updateCodeBlockBgPath() {
        ensureCodeBlockBgLayer()
        guard codeBlockBgLayerInstalled,
              let storage = textStorage,
              let layoutManager = textLayoutManager else {
            codeBlockBgLayer.path = nil
            return
        }
        codeBlockBgLayer.path = CodeBandPath.make(
            storage: storage,
            layoutManager: layoutManager,
            inset: textContainerOrigin,
            containerWidth: textContainer?.size.width ?? bounds.width
        )
    }
}
#endif
