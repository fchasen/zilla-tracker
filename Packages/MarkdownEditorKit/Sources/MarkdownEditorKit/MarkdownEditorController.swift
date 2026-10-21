import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class MarkdownEditorController: NSObject, NSTextStorageDelegate, NSTextContentStorageDelegate {
    public struct ObserverToken: Hashable, Sendable {
        let id: UUID
    }

    public let textStorage: NSTextStorage
    public let textContentStorage: NSTextContentStorage
    public let textLayoutManager: NSTextLayoutManager
    public let textContainer: NSTextContainer
    public let undoManager: UndoManager

    public var theme: MarkdownEditorTheme {
        didSet {
            guard theme != oldValue else { return }
            restyler.theme = theme
            withoutBinding { restyler.restyleAll(textStorage) }
            textLayoutManager.invalidateLayout(for: textContentStorage.documentRange)
            requestHostRedisplay()
        }
    }

    public private(set) var inlineContentRules: [InlineContentRule]
    public private(set) var inlineContentProvider: InlineContentProvider?
    public var keymap: Keymap = .mac
    public var isEditable: Bool = true
    public var allowsCheckboxToggle: Bool = false

    public weak var hostTextView: PlatformTextView? {
        didSet {
            guard hostTextView !== oldValue else { return }
            onHostTextViewChange?(hostTextView)
        }
    }

    public var onHostTextViewChange: ((PlatformTextView?) -> Void)?
    public var onSelectionChanged: ((NSRange) -> Void)?
    public var intrinsicSizeInvalidator: (() -> Void)?

    public private(set) var plugins: [EditorPlugin] = []

    var textSink: ((String) -> Void)?
    var lastPushed: String
    var bindingDirty = false
    var originalText: String
    var serializedAtLoad: String
    var restyler: Restyler
    let normalizer = Normalizer()
    private(set) var isLoading = false
    private(set) var isRestyling = false
    private var isProcessingEdit = false
    var commandDepth = 0
    var isSettingMarkedText = false
    var isWritingToolsActive = false
    var usesNativeListEditing: Bool
    private var deferredEdits: [() -> Void] = []
    private var deferredDrainScheduled = false
    var pendingInput: TypedInput?
    var headlessTypingAttributes: [NSAttributedString.Key: Any] = [:]
    lazy var editSession = EditSession(controller: self)
    private var pendingChange: DocumentChange?
    private var flushScheduled = false
    private let layoutDelegate = LayoutManagerDelegate()
    private var pluginStates: [AnyPluginKey: Any] = [:]
    private var documentObservers: [(UUID, (DocumentChange) -> Void)] = []
    private var selectionObservers: [(UUID, (NSRange) -> Void)] = []
    var headlessSelection = NSRange(location: 0, length: 0)

    public init(
        markdown: String = "",
        theme: MarkdownEditorTheme = .default,
        inlineContentRules: [InlineContentRule] = [],
        inlineContentProvider: InlineContentProvider? = nil,
        undoManager: UndoManager = UndoManager()
    ) {
        self.theme = theme
        self.inlineContentRules = inlineContentRules
        self.inlineContentProvider = inlineContentProvider
        self.undoManager = undoManager
        self.restyler = Restyler(theme: theme)
        self.textStorage = NSTextStorage()
        self.textContentStorage = NSTextContentStorage()
        self.textLayoutManager = NSTextLayoutManager()
        self.textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        self.lastPushed = markdown
        self.originalText = markdown
        self.serializedAtLoad = markdown
        #if canImport(AppKit) && os(macOS)
        self.usesNativeListEditing = true
        #else
        self.usesNativeListEditing = false
        #endif
        super.init()
        textContentStorage.textStorage = textStorage
        textContentStorage.delegate = self
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        layoutDelegate.controller = self
        textLayoutManager.delegate = layoutDelegate
        textStorage.delegate = self
        setMarkdown(markdown)
    }

    public func markdown() -> String {
        let serialized = serialize()
        return serialized == serializedAtLoad ? originalText : serialized
    }

    func serialize() -> String {
        MarkdownWriter().markdown(from: textStorage)
    }

    public func setMarkdown(_ markdown: String) {
        isLoading = true
        unmarkHostText()
        let loaded = MarkdownLoader(
            inlineContentRules: inlineContentRules,
            inlineContentProvider: inlineContentProvider
        ).load(markdown)
        let previousLength = textStorage.length
        textStorage.beginEditing()
        textStorage.setAttributedString(loaded)
        restyler.restyleAll(textStorage)
        textStorage.endEditing()
        isLoading = false
        undoManager.removeAllActions()
        let activeManager = editSession.undoManager
        if activeManager !== undoManager { activeManager.removeAllActions() }
        pendingInput = nil
        pendingChange = nil
        deferredEdits.removeAll()
        originalText = markdown
        lastPushed = markdown
        bindingDirty = false
        serializedAtLoad = serialize()
        let caret = min(currentSelection.location, textStorage.length)
        headlessSelection = NSRange(location: caret, length: 0)
        if caret < textStorage.length {
            applyTypingAttributes(typingAttributes(at: caret))
        } else {
            applyTypingAttributes(typingAttributes(for: .paragraph, textLists: []))
            if caret > 0, (textStorage.string as NSString).character(at: caret - 1) != MarkdownParagraph.separator {
                applyTypingAttributes(typingAttributes(at: caret))
            }
        }
        intrinsicSizeInvalidator?()
        fanoutDocumentChange(DocumentChange(
            editedRange: NSRange(location: 0, length: textStorage.length),
            changeInLength: textStorage.length - previousLength,
            origin: .load
        ))
    }

    public func setInlineContent(rules: [InlineContentRule], provider: InlineContentProvider?) {
        let current = markdown()
        let pushed = lastPushed
        inlineContentRules = rules
        inlineContentProvider = provider
        setMarkdown(current)
        lastPushed = pushed
    }

    func applyExternalText(_ text: String) {
        guard text != lastPushed else { return }
        setMarkdown(text)
    }

    func withoutBinding(_ work: () -> Void) {
        let wasRestyling = isRestyling
        isRestyling = true
        defer { isRestyling = wasRestyling }
        work()
    }

    func pushBinding() {
        guard !isLoading, !hostHasMarkedText, !isSettingMarkedText, bindingDirty else { return }
        bindingDirty = false
        let serialized = serialize()
        let value = serialized == serializedAtLoad ? originalText : serialized
        guard value != lastPushed else { return }
        lastPushed = value
        textSink?(value)
    }

    public var currentSelection: NSRange {
        #if canImport(AppKit) && os(macOS)
        if let hostTextView { return hostTextView.selectedRange() }
        #elseif canImport(UIKit)
        if let hostTextView { return hostTextView.selectedRange }
        #endif
        return headlessSelection
    }

    public func setSelection(_ range: NSRange) {
        let clamped = Normalizer.clamp(range, to: textStorage.length)
        headlessSelection = clamped
        #if canImport(AppKit) && os(macOS)
        hostTextView?.setSelectedRange(clamped)
        #elseif canImport(UIKit)
        hostTextView?.selectedRange = clamped
        #endif
    }

    var hostHasMarkedText: Bool {
        guard let hostTextView else { return false }
        #if canImport(AppKit) && os(macOS)
        return hostTextView.hasMarkedText()
        #elseif canImport(UIKit)
        return hostTextView.markedTextRange != nil
        #else
        return false
        #endif
    }

    var hostMarkedRange: NSRange? {
        guard let hostTextView else { return nil }
        #if canImport(AppKit) && os(macOS)
        guard hostTextView.hasMarkedText() else { return nil }
        let range = hostTextView.markedRange()
        return range.location == NSNotFound ? nil : range
        #elseif canImport(UIKit)
        guard let marked = hostTextView.markedTextRange else { return nil }
        let start = hostTextView.offset(from: hostTextView.beginningOfDocument, to: marked.start)
        let end = hostTextView.offset(from: hostTextView.beginningOfDocument, to: marked.end)
        return NSRange(location: start, length: max(0, end - start))
        #else
        return nil
        #endif
    }

    func unmarkHostText() {
        guard hostHasMarkedText, let hostTextView else { return }
        hostTextView.unmarkText()
    }

    var hostTypingAttributes: [NSAttributedString.Key: Any] {
        #if canImport(AppKit) && os(macOS)
        if let hostTextView { return hostTextView.typingAttributes }
        #elseif canImport(UIKit)
        if let hostTextView { return hostTextView.typingAttributes }
        #endif
        return headlessTypingAttributes
    }

    func applyTypingAttributes(_ attributes: [NSAttributedString.Key: Any]) {
        headlessTypingAttributes = attributes
        #if canImport(AppKit) && os(macOS)
        hostTextView?.typingAttributes = attributes
        #elseif canImport(UIKit)
        hostTextView?.typingAttributes = attributes
        #endif
    }

    func typingAttributes(for block: MarkdownBlock, textLists: [NSTextList], intent: MarkdownInlineIntent = []) -> [NSAttributedString.Key: Any] {
        let style = restyler.paragraphStyle(for: block, textLists: textLists)
        return restyler.typingAttributes(for: block, intent: intent, paragraphStyle: style)
    }

    func typingAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
        let info = paragraphInfo(at: location)
        var intent: MarkdownInlineIntent = []
        if location > info.content.location, location - 1 < textStorage.length {
            intent = textStorage.markdownInlineIntent(at: location - 1).intersection(.markdownMarks)
        }
        return typingAttributes(for: info.block, textLists: info.lists, intent: intent)
    }

    func adjustedTypingAttributes(_ proposed: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = proposed
        attributes.removeValue(forKey: .markdownLiteral)
        attributes.removeValue(forKey: .attachment)
        if attributes.markdownBlock == nil {
            let fallback = typingAttributes(at: currentSelection.location)
            attributes.markdownBlock = fallback.markdownBlock
            if attributes[.paragraphStyle] == nil { attributes[.paragraphStyle] = fallback[.paragraphStyle] }
        }
        if attributes.markdownBlock?.isCode == true {
            attributes.markdownInlineIntent = []
            attributes.removeValue(forKey: .link)
        }
        attributes.markdownInlineIntent = attributes.markdownInlineIntent.subtracting(.softBreak)
        return attributes
    }

    public func caretRect() -> CGRect? {
        rect(forCharacterAt: currentSelection.location)
    }

    public func rect(forCharacterAt index: Int) -> CGRect? {
        guard index >= 0, index <= textStorage.length else { return nil }
        let docStart = textContentStorage.documentRange.location
        guard let location = textContentStorage.location(docStart, offsetBy: index) else { return nil }
        var rect: CGRect?
        textLayoutManager.enumerateTextSegments(
            in: NSTextRange(location: location),
            type: .standard,
            options: [.upstreamAffinity, .rangeNotRequired]
        ) { _, frame, _, _ in
            rect = frame
            return false
        }
        guard var result = rect else { return nil }
        #if canImport(AppKit) && os(macOS)
        if let hostTextView {
            result.origin.x += hostTextView.textContainerOrigin.x
            result.origin.y += hostTextView.textContainerOrigin.y
        }
        #elseif canImport(UIKit)
        if let hostTextView {
            result.origin.x += hostTextView.textContainerInset.left
            result.origin.y += hostTextView.textContainerInset.top
        }
        #endif
        return result
    }

    public func inlineContentKind(at index: Int) -> String? {
        textStorage.markdownSourceAttachment(at: index)?.contentKind
    }

    public func register(plugin: EditorPlugin) {
        plugins.append(plugin)
    }

    public func pluginState<State>(for key: PluginKey<State>) -> State? {
        pluginStates[key.any] as? State
    }

    public func setPluginState<State>(_ state: State, for key: PluginKey<State>) {
        pluginStates[key.any] = state
    }

    public func clearPluginState<State>(for key: PluginKey<State>) {
        pluginStates.removeValue(forKey: key.any)
    }

    @discardableResult
    public func addOnDocumentChange(_ handler: @escaping (DocumentChange) -> Void) -> ObserverToken {
        let id = UUID()
        documentObservers.append((id, handler))
        return ObserverToken(id: id)
    }

    @discardableResult
    public func addOnSelectionChanged(_ handler: @escaping (NSRange) -> Void) -> ObserverToken {
        let id = UUID()
        selectionObservers.append((id, handler))
        return ObserverToken(id: id)
    }

    public func removeObserver(_ token: ObserverToken) {
        documentObservers.removeAll { $0.0 == token.id }
        selectionObservers.removeAll { $0.0 == token.id }
    }

    func fanoutDocumentChange(_ change: DocumentChange) {
        for plugin in plugins { plugin.documentDidChange(change, controller: self) }
        for (_, handler) in documentObservers { handler(change) }
    }

    func selectionDidChange(_ range: NSRange) {
        headlessSelection = range
        onSelectionChanged?(range)
        for (_, handler) in selectionObservers { handler(range) }
    }

    func isLocationInCode(_ location: Int) -> Bool {
        let total = textStorage.length
        guard total > 0 else { return false }
        let info = paragraphInfo(at: location)
        if info.block.isCode { return true }
        guard location > info.content.location, location < NSMaxRange(info.content) else { return false }
        return textStorage.markdownInlineIntent(at: location - 1).contains(.code)
            && textStorage.markdownInlineIntent(at: location).contains(.code)
    }

    var isApplyingCommand: Bool { commandDepth > 0 || editSession.isPerforming }

    func hostShouldChangeText(in range: NSRange, replacement: String?) -> Bool {
        if !isApplyingCommand, let replacement {
            for plugin in plugins {
                if plugin.props.handleTextInput?(self, range, replacement) == true { return false }
            }
        }
        return shouldChangeText(in: range, replacement: replacement)
    }

    func shouldChangeText(in range: NSRange, replacement: String?) -> Bool {
        guard !isApplyingCommand else { return true }
        let manager = editSession.undoManager
        guard !manager.isUndoing, !manager.isRedoing else {
            pendingInput = nil
            return true
        }
        if let replacement, !replacement.isEmpty, !hostHasMarkedText, !isSettingMarkedText,
           redirectTypingIntoAtom(range: range, text: replacement) {
            pendingInput = nil
            return false
        }
        recordTypedInput(range: range, replacement: replacement)
        return true
    }

    @discardableResult
    func performEdit(
        _ actionName: String,
        ranges: [NSRange],
        replacements: [String]?,
        ignoringEditability: Bool = false,
        selection: NSRange? = nil,
        _ body: (NSTextStorage) -> Void
    ) -> Bool {
        let manager = editSession.undoManager
        let opensGroup = !manager.groupsByEvent && manager.groupingLevel == 0 && manager.isUndoRegistrationEnabled
        if opensGroup { manager.beginUndoGrouping() }
        commandDepth += 1
        let applied = editSession.perform(
            actionName: actionName,
            ranges: ranges,
            replacements: replacements,
            ignoringEditability: ignoringEditability,
            body
        )
        commandDepth -= 1
        if opensGroup { manager.endUndoGrouping() }
        if applied, let selection { setSelection(selection) }
        flushDocumentChanges()
        return applied
    }

    @discardableResult
    func replace(
        _ range: NSRange,
        with replacement: NSAttributedString,
        actionName: String,
        selection: NSRange?,
        ignoringEditability: Bool = false
    ) -> Bool {
        let target = Normalizer.clamp(range, to: textStorage.length)
        return performEdit(
            actionName,
            ranges: [target],
            replacements: [replacement.string],
            ignoringEditability: ignoringEditability,
            selection: selection
        ) { storage in
            storage.replaceCharacters(in: target, with: replacement)
        }
    }

    @discardableResult
    func editAttributes(
        in range: NSRange,
        actionName: String,
        ignoringEditability: Bool = false,
        _ body: (NSTextStorage) -> Void
    ) -> Bool {
        let target = Normalizer.clamp(range, to: textStorage.length)
        guard target.length > 0 else { return false }
        let selection = currentSelection
        return performEdit(
            actionName,
            ranges: [target],
            replacements: nil,
            ignoringEditability: ignoringEditability,
            selection: selection,
            body
        )
    }

    func deferEdit(_ work: @escaping () -> Void) {
        deferredEdits.append(work)
        guard !deferredDrainScheduled else { return }
        deferredDrainScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.drainDeferredEdits()
        }
    }

    func drainDeferredEdits() {
        deferredDrainScheduled = false
        while !deferredEdits.isEmpty {
            let work = deferredEdits.removeFirst()
            work()
        }
    }

    func flushDocumentChanges() {
        guard let change = pendingChange else { return }
        pendingChange = nil
        invalidateDecorations(after: change)
        fanoutDocumentChange(change)
        if change.origin == .user { scheduleInputRules() }
    }

    func invalidateDecorations(after change: DocumentChange) {
        let total = textStorage.length
        guard change.origin != .load, total > 0 else { return }
        let ns = textStorage.string as NSString
        let edited = Normalizer.clamp(change.editedRange, to: total)
        if change.origin == .user, change.changeInLength == edited.length,
           ns.substring(with: edited).rangeOfCharacter(from: .newlines) == nil {
            return
        }
        var start = ns.paragraphRange(for: NSRange(location: edited.location, length: 0)).location
        if start > 0 { start = ns.paragraphRange(for: NSRange(location: start - 1, length: 0)).location }
        var end = NSMaxRange(ns.paragraphRange(for: NSRange(location: min(NSMaxRange(edited), total), length: 0)))
        if end < total { end = NSMaxRange(ns.paragraphRange(for: NSRange(location: end, length: 0))) }
        while end < total {
            let paragraph = ns.paragraphRange(for: NSRange(location: end, length: 0))
            guard !Normalizer.effectiveTextLists(in: textStorage, at: paragraph.location).isEmpty else { break }
            end = NSMaxRange(paragraph)
        }
        let docStart = textContentStorage.documentRange.location
        guard let from = textContentStorage.location(docStart, offsetBy: start),
              let to = textContentStorage.location(docStart, offsetBy: end),
              let range = NSTextRange(location: from, end: to) else { return }
        textLayoutManager.invalidateLayout(for: range)
        requestHostRedisplay()
    }

    func requestHostRedisplay() {
        #if canImport(AppKit) && os(macOS)
        hostTextView?.needsLayout = true
        hostTextView?.needsDisplay = true
        #elseif canImport(UIKit)
        hostTextView?.setNeedsLayout()
        hostTextView?.setNeedsDisplay()
        #endif
    }

    public func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length,
              let style = textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
              !style.textLists.isEmpty,
              let stripped = style.mutableCopy() as? NSMutableParagraphStyle else { return nil }
        stripped.textLists = []
        let element = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: range))
        element.addAttribute(.paragraphStyle, value: stripped, range: NSRange(location: 0, length: element.length))
        return NSTextParagraph(attributedString: element)
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.flushDocumentChanges()
        }
    }

    private func recordChange(_ editedRange: NSRange, delta: Int, origin: DocumentChange.Origin) {
        if let existing = pendingChange {
            pendingChange = DocumentChange(
                editedRange: existing.editedRange.merged(withEdit: editedRange, changeInLength: delta),
                changeInLength: existing.changeInLength + delta,
                origin: existing.origin == origin ? origin : (origin == .user ? existing.origin : origin)
            )
        } else {
            pendingChange = DocumentChange(editedRange: editedRange, changeInLength: delta, origin: origin)
        }
    }

    func markedRangeForNormalization(_ editedRange: NSRange) -> NSRange? {
        var marked = hostMarkedRange
        if isSettingMarkedText {
            marked = marked.map { NSUnionRange($0, editedRange) } ?? editedRange
        }
        return marked
    }

    public func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: PlatformTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard !isLoading, !isRestyling, !isProcessingEdit else { return }
        PasteSanitizer.captureForeignAttributes(in: textStorage, range: editedRange)
    }

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: PlatformTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if !isLoading { bindingDirty = true }
        guard !isLoading, !isRestyling, !isProcessingEdit else { return }
        isProcessingEdit = true
        defer { isProcessingEdit = false }
        let manager = editSession.undoManager
        let isUndo = manager.isUndoing || manager.isRedoing
        let marked = markedRangeForNormalization(editedRange)
        let characters = editedMask.contains(.editedCharacters)
        if isUndo {
            let affected = Normalizer.affectedRange(for: editedRange, in: textStorage)
            restyler.restyle(textStorage, in: affected, excluding: marked)
        } else {
            let result = normalizer.normalizeRecordingRevert(
                textStorage,
                editedRange: editedRange,
                changeInLength: characters ? delta : 0,
                markedRange: marked
            )
            result.revert?.registerUndo(on: manager, storage: textStorage)
            restyler.restyle(textStorage, in: result.touched, excluding: marked)
        }
        let origin: DocumentChange.Origin = isUndo ? .undo : (isApplyingCommand ? .command : .user)
        recordChange(editedRange, delta: characters ? delta : 0, origin: origin)
        pushBinding()
        if characters { intrinsicSizeInvalidator?() }
        scheduleFlush()
    }
}

struct TypedInput: Equatable {
    var location: Int
    var text: String

    var caret: Int { location + (text as NSString).length }
}

struct ParagraphInfo {
    var range: NSRange
    var content: NSRange
    var block: MarkdownBlock
    var lists: [NSTextList]
    var hasSeparator: Bool

    var isEmpty: Bool { content.length == 0 }
    var isTrailingEmpty: Bool { range.length == 0 }
}

extension MarkdownEditorController {
    func paragraphInfo(at location: Int) -> ParagraphInfo {
        let storage = textStorage
        let total = storage.length
        let ns = storage.string as NSString
        let clamped = max(0, min(location, total))
        let endsWithSeparator = total > 0 && ns.character(at: total - 1) == MarkdownParagraph.separator
        if total == 0 || (clamped == total && endsWithSeparator) {
            let typing = hostTypingAttributes
            let fallbackBlock: MarkdownBlock
            let fallbackLists: [NSTextList]
            if let block = typing.markdownBlock {
                fallbackBlock = block
                fallbackLists = (typing[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
            } else if total > 0 {
                let previous = storage.markdownBlock(at: total - 1) ?? .paragraph
                fallbackBlock = previous
                fallbackLists = Self.textLists(in: storage, at: total - 1)
            } else {
                fallbackBlock = .paragraph
                fallbackLists = []
            }
            let empty = NSRange(location: total, length: 0)
            return ParagraphInfo(range: empty, content: empty, block: fallbackBlock, lists: fallbackLists, hasSeparator: false)
        }
        let paragraph = ns.paragraphRange(for: NSRange(location: clamped, length: 0))
        let hasSeparator = paragraph.length > 0 && ns.character(at: NSMaxRange(paragraph) - 1) == MarkdownParagraph.separator
        let content = NSRange(location: paragraph.location, length: paragraph.length - (hasSeparator ? 1 : 0))
        return ParagraphInfo(
            range: paragraph,
            content: content,
            block: storage.markdownBlock(at: paragraph.location) ?? .paragraph,
            lists: Self.textLists(in: storage, at: paragraph.location),
            hasSeparator: hasSeparator
        )
    }

    func previousParagraphInfo(before info: ParagraphInfo) -> ParagraphInfo? {
        guard info.range.location > 0 else { return nil }
        return paragraphInfo(at: info.range.location - 1)
    }

    func nextParagraphInfo(after info: ParagraphInfo) -> ParagraphInfo? {
        guard info.hasSeparator else { return nil }
        let next = NSMaxRange(info.range)
        guard next < textStorage.length else { return nil }
        return paragraphInfo(at: next)
    }

    func selectedParagraphs(in range: NSRange) -> [ParagraphInfo] {
        let total = textStorage.length
        let target = Normalizer.clamp(range, to: total)
        var result: [ParagraphInfo] = []
        var location = paragraphInfo(at: target.location).range.location
        while true {
            let info = paragraphInfo(at: location)
            result.append(info)
            let next = NSMaxRange(info.range)
            guard info.range.length > 0, next < NSMaxRange(target), next < total else { break }
            location = next
        }
        return result
    }

    static func textLists(in storage: NSAttributedString, at index: Int) -> [NSTextList] {
        guard index >= 0, index < storage.length,
              let style = storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
        else { return [] }
        return style.textLists
    }

    func paragraphAttributes(for block: MarkdownBlock, textLists: [NSTextList]) -> [NSAttributedString.Key: Any] {
        typingAttributes(for: block, textLists: textLists)
    }

    func reblocked(_ string: NSAttributedString, block: MarkdownBlock, textLists: [NSTextList]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: string)
        let full = NSRange(location: 0, length: result.length)
        guard full.length > 0 else { return result }
        result.addAttribute(.markdownBlock, value: block, range: full)
        result.addAttribute(.paragraphStyle, value: restyler.paragraphStyle(for: block, textLists: textLists), range: full)
        if block.isCode {
            result.removeAttribute(.markdownInlineIntent, range: full)
            result.removeAttribute(.link, range: full)
            result.removeAttribute(.markdownLiteral, range: full)
        }
        return result
    }

    func separator(block: MarkdownBlock, textLists: [NSTextList]) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: paragraphAttributes(for: block, textLists: textLists))
    }
}
