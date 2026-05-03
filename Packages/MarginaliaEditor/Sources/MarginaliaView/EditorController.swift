import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class EditorController {

    public typealias Dialect = MarginaliaView.Dialect

    public let textStorage: NSTextStorage
    public let contentStorage: NSTextContentStorage
    public let layoutManager: NSTextLayoutManager
    public let textContainer: NSTextContainer

    public var theme: MarginaliaTheme {
        didSet { recompile() }
    }
    public var dialect: Dialect {
        didSet { recompile() }
    }
    public var mode: Mode {
        didSet { recompile() }
    }

    public private(set) var blocks: [BlockSegment] = []

    public let undoManager: UndoManager = UndoManager()
    public weak var hostTextView: AnyObject?
    public var intrinsicSizeInvalidator: (() -> Void)?

    private(set) var compiler: MarkdownAttributedCompiler
    private(set) var serializer: AttributedMarkdownSerializer
    private let layoutDelegate: LayoutManagerDelegate
    private var storageObserver: NSObjectProtocol?
    private var applyingMarkdown = false

    public init(
        initialMarkdown: String = "",
        theme: MarginaliaTheme = .default,
        dialect: Dialect = .commonMark,
        mode: Mode = .rich,
        containerSize: CGSize = CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
    ) throws {
        self.theme = theme
        self.dialect = dialect
        self.mode = mode
        self.compiler = try MarkdownAttributedCompiler()
        self.serializer = AttributedMarkdownSerializer()

        self.textStorage = NSTextStorage()
        self.contentStorage = NSTextContentStorage()
        self.contentStorage.textStorage = textStorage
        self.layoutManager = NSTextLayoutManager()
        self.contentStorage.addTextLayoutManager(layoutManager)
        self.textContainer = NSTextContainer(size: containerSize)
        self.layoutManager.textContainer = textContainer

        self.layoutDelegate = LayoutManagerDelegate()
        layoutManager.delegate = layoutDelegate
        layoutDelegate.controller = self

        applyingMarkdown = true
        let initial = compileFor(initialMarkdown)
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: initial)
        applyingMarkdown = false
        resegment()

        storageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textStorage,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.applyingMarkdown else { return }
            if self.textStorage.editedMask.contains(.editedCharacters) {
                self.demoteEmptyStyledLines()
                self.resegment()
                self.intrinsicSizeInvalidator?()
            }
        }
    }

    /// After a character edit, scan the edited paragraphs and reset any
    /// non-paragraph block attribution on lines whose content text is now
    /// empty. Without this, deleting all of a heading's text leaves the
    /// heading block attribute on the trailing newline (or on the text
    /// view's `typingAttributes`) so the next keystroke continues to
    /// render in heading style.
    private func demoteEmptyStyledLines() {
        let plainAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont,
            .foregroundColor: theme.foregroundColor,
            .paragraphStyle: NSParagraphStyle(),
            .marginaliaBlock: BlockAttribute(tag: .paragraph)
        ]
        // Storage cleared entirely: nothing to mutate, but the typing
        // attributes on the host text view still carry the prior heading /
        // list style. Reset them.
        if textStorage.length == 0 {
            applyTypingAttributes(plainAttrs)
            return
        }
        let editedRange = textStorage.editedRange
        let ns = textStorage.string as NSString
        guard editedRange.length >= 0, editedRange.location >= 0 else { return }
        let probeRange = NSRange(
            location: max(0, min(editedRange.location, ns.length)),
            length: 0
        )
        let lineRange = ns.paragraphRange(for: probeRange)
        guard lineRange.length > 0 else { return }

        // "Empty" means: the paragraph contains no characters other than the
        // trailing newline (and any leading attachment glyph for a task-list
        // item, which the user may have inserted intentionally).
        let lineText = ns.substring(with: lineRange)
        let stripped = lineText
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard stripped.isEmpty else { return }

        let probe = lineRange.location
        guard probe < textStorage.length,
              let block = textStorage.attribute(.marginaliaBlock, at: probe, effectiveRange: nil) as? BlockAttribute,
              block.tag != .paragraph else { return }
        // Avoid resetting list items if there's still a checkbox attachment
        // — the user may want to preserve the empty task slot.
        if textStorage.attribute(.marginaliaListItem, at: probe, effectiveRange: nil) != nil {
            return
        }

        textStorage.beginEditing()
        textStorage.addAttributes(plainAttrs, range: lineRange)
        textStorage.endEditing()
        applyTypingAttributes(plainAttrs)
    }

    /// NSTextView caches typing attributes separately from storage. After
    /// programmatic storage edits the cache still holds whatever was at
    /// the cursor before, so we have to push the desired attributes into
    /// the host explicitly.
    private func applyTypingAttributes(_ attrs: [NSAttributedString.Key: Any]) {
        #if canImport(AppKit) && os(macOS)
        if let tv = hostTextView as? NSTextView {
            tv.typingAttributes = attrs
        }
        #elseif canImport(UIKit)
        if let tv = hostTextView as? UITextView {
            tv.typingAttributes = attrs
        }
        #endif
    }

    deinit {
        if let storageObserver {
            NotificationCenter.default.removeObserver(storageObserver)
        }
    }

    public func setMarkdown(_ markdown: String) {
        let compiled = compileFor(markdown)
        replaceStorage(with: compiled)
    }

    public var text: String {
        get { markdown() }
        set { setMarkdown(newValue) }
    }

    public func markdown() -> String {
        return serializer.serialize(textStorage, dialect: dialect)
    }

    public func recompile() {
        let md = markdown()
        setMarkdown(md)
    }

    /// Storage-coord cursor position inferred from the host text view, or 0
    /// if no host is attached.
    public var currentSelection: NSRange {
        #if canImport(AppKit) && os(macOS)
        if let tv = hostTextView as? NSTextView { return tv.selectedRange() }
        #elseif canImport(UIKit)
        if let tv = hostTextView as? UITextView { return tv.selectedRange }
        #endif
        return NSRange(location: 0, length: 0)
    }

    /// Insert plain text at the host text view's cursor (or replace its
    /// selection). Cursor lands after the inserted text.
    @discardableResult
    public func insert(text: String) -> NSRange {
        snapshotForUndo()
        let result = Operations.insertText(in: textStorage, replacing: currentSelection, with: text)
        setHostSelection(result)
        return result
    }

    /// Apply an editor action against the host text view's current
    /// selection. The text view owns the selection; this is the path the
    /// `@objc` action methods call from the responder chain.
    @discardableResult
    public func perform(_ action: EditorAction) -> NSRange {
        snapshotForUndo()
        let range = currentSelection
        let resulting: NSRange
        switch action {
        case .bold:
            resulting = Operations.toggleBold(in: textStorage, range: range, theme: theme)
        case .italic:
            resulting = Operations.toggleItalic(in: textStorage, range: range, theme: theme)
        case .strikethrough:
            resulting = Operations.toggleStrikethrough(in: textStorage, range: range, theme: theme)
        case .codeSpan:
            resulting = Operations.toggleCodeSpan(in: textStorage, range: range, theme: theme)
        case .link(let url, let label):
            resulting = Operations.insertLink(
                in: textStorage,
                replacing: range,
                label: label ?? "label",
                url: url ?? "url",
                theme: theme
            )
        case .heading(let level):
            resulting = Operations.setHeading(
                in: textStorage, range: range, level: level,
                compiler: compiler, serializer: serializer,
                dialect: dialect, mode: mode, theme: theme
            )
        case .unorderedList:
            resulting = Operations.toggleUnorderedList(
                in: textStorage, range: range,
                compiler: compiler, serializer: serializer,
                dialect: dialect, mode: mode, theme: theme
            )
        case .orderedList:
            resulting = Operations.toggleOrderedList(
                in: textStorage, range: range,
                compiler: compiler, serializer: serializer,
                dialect: dialect, mode: mode, theme: theme
            )
        case .taskList:
            resulting = Operations.toggleTaskList(
                in: textStorage, range: range,
                compiler: compiler, serializer: serializer,
                dialect: dialect, mode: mode, theme: theme
            )
        case .blockquote:
            resulting = Operations.toggleBlockquote(
                in: textStorage, range: range,
                compiler: compiler, serializer: serializer,
                dialect: dialect, mode: mode, theme: theme
            )
        case .codeBlock:
            resulting = Operations.insertCodeBlock(
                in: textStorage, range: range,
                compiler: compiler, serializer: serializer,
                dialect: dialect, mode: mode, theme: theme
            )
        case .horizontalRule:
            resulting = Operations.insertHorizontalRule(
                in: textStorage, range: range,
                compiler: compiler, serializer: serializer,
                dialect: dialect, mode: mode, theme: theme
            )
        }
        setHostSelection(resulting)
        return resulting
    }

    /// Insert a link at the host text view's cursor. If the user has a
    /// non-empty selection, that text becomes the link's display label;
    /// otherwise the supplied `label` (e.g. `"bug 12345"`) is used. The URL
    /// rides on a `.link` attribute and round-trips as `[label](url)`.
    @discardableResult
    public func insertLink(label: String, url: String) -> NSRange {
        snapshotForUndo()
        let selection = currentSelection
        var actualLabel = label
        if selection.length > 0,
           selection.location + selection.length <= textStorage.length {
            let selected = (textStorage.string as NSString).substring(with: selection)
            if !selected.isEmpty {
                actualLabel = selected
            }
        }
        let result = Operations.insertLink(
            in: textStorage,
            replacing: selection,
            label: actualLabel,
            url: url,
            theme: theme
        )
        setHostSelection(result)
        return result
    }

    /// Capture the storage + selection so Cmd-Z reverts the upcoming
    /// operation. Operations mutate `textStorage` directly, which bypasses
    /// NSTextView's auto-undo path; without manual registration, Cmd-Z
    /// would skip them entirely.
    ///
    /// The closure narrows the revert to the diff range (so unrelated
    /// edits made *after* this op aren't blown away when the user finally
    /// undoes back to it). For attribute-only changes (e.g. bold toggle)
    /// the diff finds no character delta, so we fall back to full-storage
    /// replace.
    private func snapshotForUndo() {
        let preStorage = NSAttributedString(attributedString: textStorage)
        let preSelection = currentSelection
        let preLen = preStorage.length

        undoManager.registerUndo(withTarget: self) { [weak self] target in
            guard let self else { _ = target; return }
            self.snapshotForUndo()
            self.applyingMarkdown = true
            self.textStorage.beginEditing()
            let postLen = self.textStorage.length
            let preStr = preStorage.string as NSString
            let postStr = self.textStorage.string as NSString
            var leftSame = 0
            let minLen = min(preLen, postLen)
            while leftSame < minLen,
                  preStr.character(at: leftSame) == postStr.character(at: leftSame) {
                leftSame += 1
            }
            var rightSame = 0
            while rightSame < (minLen - leftSame),
                  preStr.character(at: preLen - 1 - rightSame) == postStr.character(at: postLen - 1 - rightSame) {
                rightSame += 1
            }
            let charactersChanged = (preLen != postLen) || (leftSame < minLen) || (rightSame > 0)
            if charactersChanged {
                let preDiffRange = NSRange(location: leftSame, length: preLen - leftSame - rightSame)
                let postDiffRange = NSRange(location: leftSame, length: postLen - leftSame - rightSame)
                let oldSubstring = preStorage.attributedSubstring(from: preDiffRange)
                self.textStorage.replaceCharacters(in: postDiffRange, with: oldSubstring)
            } else {
                let fullRange = NSRange(location: 0, length: postLen)
                self.textStorage.replaceCharacters(in: fullRange, with: preStorage)
            }
            self.textStorage.endEditing()
            self.applyingMarkdown = false
            self.setHostSelection(preSelection)
            self.resegment()
        }
    }

    @discardableResult
    public func toggleCheckbox(at location: Int) -> Bool {
        snapshotForUndo()
        let total = textStorage.length
        guard location >= 0, location < total else { return false }
        guard let existing = textStorage.attribute(.attachment, at: location, effectiveRange: nil) as? CheckboxAttachment,
              let listAttr = textStorage.attribute(.marginaliaListItem, at: location, effectiveRange: nil) as? ListItemAttribute,
              listAttr.kind == .task else { return false }
        let newChecked = !existing.isChecked
        let newAttachment = CheckboxAttachment()
        newAttachment.isChecked = newChecked
        let newListAttr = ListItemAttribute(
            level: listAttr.level,
            kind: .task,
            orderedIndex: listAttr.orderedIndex,
            isChecked: newChecked
        )
        let ns = textStorage.string as NSString
        let lineRange = ns.paragraphRange(for: NSRange(location: location, length: 0))
        textStorage.beginEditing()
        textStorage.addAttribute(.attachment, value: newAttachment, range: NSRange(location: location, length: 1))
        textStorage.addAttribute(.marginaliaListItem, value: newListAttr, range: lineRange)
        textStorage.endEditing()
        return true
    }

    /// Called from the text view when the user presses Return. Returns
    /// `true` if the newline was consumed by list-continuation handling;
    /// `false` if the text view should insert the newline normally.
    @discardableResult
    public func handleNewline() -> Bool {
        snapshotForUndo()
        let cursor = currentSelection.location
        if let result = InsertNewline.handle(
            in: textStorage,
            cursor: cursor,
            compiler: compiler,
            serializer: serializer,
            dialect: dialect,
            mode: mode,
            theme: theme
        ) {
            setHostSelection(result)
            return true
        }
        // Heading lines: a Return ends the heading. The new paragraph (and
        // the trailing portion of the original line, if the user pressed
        // Return mid-heading) drops back to plain paragraph styling so
        // their typing isn't stuck in a giant bold font.
        if isHeadingAt(location: cursor) {
            return splitHeadingIntoParagraph(at: cursor)
        }
        return false
    }

    private func isHeadingAt(location: Int) -> Bool {
        let total = textStorage.length
        guard total > 0 else { return false }
        let probe = max(0, min(location, total - 1))
        guard let block = textStorage.attribute(
            .marginaliaBlock, at: probe, effectiveRange: nil
        ) as? BlockAttribute else { return false }
        return block.tag == .heading
    }

    private func splitHeadingIntoParagraph(at cursor: Int) -> Bool {
        let ns = textStorage.string as NSString
        let lineRange = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
        let trailingLength = max(0, lineRange.location + lineRange.length - cursor)

        let plainAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont,
            .foregroundColor: theme.foregroundColor,
            .paragraphStyle: NSParagraphStyle(),
            .marginaliaBlock: BlockAttribute(tag: .paragraph)
        ]
        let inserted = NSAttributedString(string: "\n", attributes: plainAttrs)

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: cursor, length: 0), with: inserted)
        if trailingLength > 0 {
            let trailingRange = NSRange(location: cursor + 1, length: trailingLength)
            textStorage.addAttributes(plainAttrs, range: trailingRange)
        }
        textStorage.endEditing()
        setHostSelection(NSRange(location: cursor + 1, length: 0))
        return true
    }

    private func setHostSelection(_ range: NSRange) {
        let total = textStorage.length
        let safeLocation = max(0, min(range.location, total))
        let remaining = max(0, total - safeLocation)
        let safe = NSRange(
            location: safeLocation,
            length: max(0, min(range.length, remaining))
        )
        #if canImport(AppKit) && os(macOS)
        if let tv = hostTextView as? NSTextView { tv.setSelectedRange(safe) }
        #elseif canImport(UIKit)
        if let tv = hostTextView as? UITextView { tv.selectedRange = safe }
        #endif
    }

    // MARK: - private

    private func compileFor(_ markdown: String) -> NSAttributedString {
        return compiler.compile(markdown, dialect: dialect, mode: mode, theme: theme)
    }

    private func replaceStorage(with attributed: NSAttributedString) {
        applyingMarkdown = true
        let total = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: total, with: attributed)
        textStorage.endEditing()
        applyingMarkdown = false
        resegment()
    }

    private func resegment() {
        var segs: [BlockSegment] = []
        let total = textStorage.length
        guard total > 0 else { self.blocks = []; return }
        var cursor = 0
        while cursor < total {
            var range = NSRange(location: cursor, length: 0)
            let attr = textStorage.attribute(
                .marginaliaBlock,
                at: cursor,
                longestEffectiveRange: &range,
                in: NSRange(location: cursor, length: total - cursor)
            )
            if let block = attr as? BlockAttribute {
                let listAttr = textStorage.attribute(
                    .marginaliaListItem, at: cursor, effectiveRange: nil
                ) as? ListItemAttribute
                segs.append(BlockSegment(
                    range: range,
                    tag: block.tag,
                    level: block.level,
                    blockquoteDepth: block.blockquoteDepth,
                    language: block.language,
                    listLevel: listAttr?.level ?? 0,
                    orderedIndex: listAttr?.orderedIndex,
                    isChecked: listAttr?.isChecked,
                    firstInListItem: false
                ))
            }
            if range.length == 0 { break }
            cursor = range.location + range.length
        }
        self.blocks = segs
    }
}
