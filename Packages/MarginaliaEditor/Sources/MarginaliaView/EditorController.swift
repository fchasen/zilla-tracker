import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The single source of truth for one editor instance.
///
/// Owns the TextKit 2 object graph (`NSTextStorage` →
/// `NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer`),
/// runs the syntax pipeline, and pushes attribute changes back into the
/// text storage. The platform-specific representable wrappers
/// (`MarginaliaViewMac` / `MarginaliaViewIOS`) read it but never own the
/// storage themselves — replacing the text view doesn't lose state.
public final class EditorController {

    public let textStorage: NSTextStorage
    public let contentStorage: NSTextContentStorage
    public let layoutManager: NSTextLayoutManager
    public let textContainer: NSTextContainer

    public var theme: MarginaliaTheme {
        didSet { refresh() }
    }
    public var dialect: Highlighter.Dialect {
        didSet { rebuildHighlighter(); refresh() }
    }

    /// Most recent block-level classification, computed alongside highlights.
    public private(set) var blockRegions: [BlockRegion] = []

    /// Markup ranges (e.g. `**`, `#`, `>`) that should be visually hidden when
    /// the cursor is *not* on those lines (caret-aware focus mode).
    public private(set) var markupRanges: [NSRange] = []

    public var selection: NSRange = NSRange(location: 0, length: 0) {
        didSet { recomputeHidden() }
    }

    public private(set) var hiddenRanges: [NSRange] = []

    /// The platform text view backed by `textContainer`. Held weakly so the
    /// view can be torn down by SwiftUI without leaking; set by the
    /// `MarginaliaTextView*` representables in `make…View`. The toolbar's
    /// `applyEdit` path uses this to push the new selection back into the
    /// view after replacing storage.
    public weak var hostTextView: AnyObject?

    /// Hook the representable installs so storage edits invalidate the
    /// host view's intrinsic content size — that's how the editor grows
    /// with its content in `EditorSizing.fitsContent` mode.
    public var intrinsicSizeInvalidator: (() -> Void)?

    private var highlighter: Highlighter
    private let parser: MarkdownParser
    private let layoutDelegate: LayoutManagerDelegate
    private var refreshing = false
    private var storageObserver: NSObjectProtocol?

    public init(
        initialText: String = "",
        theme: MarginaliaTheme = .default,
        dialect: Highlighter.Dialect = .commonMark,
        containerSize: CGSize = CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
    ) throws {
        self.theme = theme
        self.dialect = dialect
        self.highlighter = try Highlighter(dialect: dialect, theme: theme)
        self.parser = try MarkdownParser(grammar: .block)

        self.textStorage = NSTextStorage(string: initialText)
        self.contentStorage = NSTextContentStorage()
        self.contentStorage.textStorage = textStorage
        self.layoutManager = NSTextLayoutManager()
        self.contentStorage.addTextLayoutManager(layoutManager)
        self.textContainer = NSTextContainer(size: containerSize)
        self.layoutManager.textContainer = textContainer

        self.layoutDelegate = LayoutManagerDelegate()

        layoutManager.delegate = layoutDelegate
        layoutDelegate.controller = self

        storageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textStorage,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleRefresh()
            self?.intrinsicSizeInvalidator?()
        }

        refresh()
    }

    deinit {
        if let storageObserver {
            NotificationCenter.default.removeObserver(storageObserver)
        }
    }

    /// Replace the entire text. Triggers a full re-parse + re-highlight.
    public func setText(_ text: String) {
        let range = NSRange(location: 0, length: textStorage.length)
        textStorage.replaceCharacters(in: range, with: text)
    }

    public var text: String {
        get { textStorage.string }
        set { setText(newValue) }
    }

    /// Apply a single edit. Caller is responsible for ensuring the edit's
    /// NSRange is valid against the current `text`.
    public func applyEdit(replacing range: NSRange, with replacement: String) {
        textStorage.replaceCharacters(in: range, with: replacement)
        scheduleRefresh()
    }

    /// Apply a toolbar-style edit: replace the entire text with `result.text`
    /// and move the cursor to `result.selection`, clamping the selection to
    /// the new text bounds. Also pushes the new selection into the host text
    /// view so the user sees the cursor land in the right place.
    ///
    /// This is the path the formatting toolbar uses, so it must tolerate a
    /// stale or out-of-bounds input range without crashing — that's the
    /// regression behind the `NSRangeException` from the task-list button
    /// when the binding's selection points past the current text.
    public func applyEdit(_ result: EditResult) {
        let length = (result.text as NSString).length
        let location = max(0, min(result.selection.location, length))
        let remaining = max(0, length - location)
        let clamped = NSRange(
            location: location,
            length: max(0, min(result.selection.length, remaining))
        )
        setText(result.text)
        // Clamp the cached selection BEFORE refreshing — `recomputeHidden`
        // (called inside `refreshNow`) reads `self.selection` and would
        // crash on `lineRange(for:)` if it's still pointing into the old,
        // longer text.
        selection = clamped
        // Apply highlights + paragraph styles synchronously so the freshly
        // inserted text doesn't render unstyled for one frame. Without this,
        // a newly continued list line is rendered without its hanging-indent
        // paragraph style until the next runloop tick.
        refreshNow()
        #if canImport(AppKit) && os(macOS)
        if let tv = hostTextView as? NSTextView {
            tv.setSelectedRange(clamped)
        }
        #elseif canImport(UIKit)
        if let tv = hostTextView as? UITextView {
            tv.selectedRange = clamped
        }
        #endif
    }

    /// Clamps `range` to the current text's bounds, useful when the toolbar
    /// receives a stale selection (e.g. from a `.constant` SwiftUI binding)
    /// and needs to defend against `NSRangeException` in `EditingOps`.
    public func clampedRange(_ range: NSRange) -> NSRange {
        let length = textStorage.length
        let location = max(0, min(range.location, length))
        let remaining = max(0, length - location)
        return NSRange(
            location: location,
            length: max(0, min(range.length, remaining))
        )
    }

    /// Force the highlight + classify pass to run synchronously, e.g. from tests.
    public func refreshNow() {
        runRefresh()
    }

    // MARK: - private

    private func rebuildHighlighter() {
        if let h = try? Highlighter(dialect: dialect, theme: theme) {
            self.highlighter = h
        }
    }

    private func scheduleRefresh() {
        runRefresh()
    }

    private func refresh() {
        runRefresh()
    }

    private func runRefresh() {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let source = textStorage.string

        if let tree = parser.parse(source), let root = tree.rootNode {
            blockRegions = BlockClassifier.classify(rootNode: root, mapping: parser.mapping)
        } else {
            blockRegions = []
        }

        let runs = highlighter.runs(for: source, blockRegions: blockRegions)
        markupRanges = highlighter.markupRanges(for: source, blockRegions: blockRegions)

        applyAttributes(runs: runs, full: source)
        recomputeHidden()
    }

    private func applyAttributes(runs: [Highlighter.Run], full source: String) {
        let total = NSRange(location: 0, length: (source as NSString).length)
        textStorage.beginEditing()
        // Reset to base style first so removed markers don't leave stale attrs
        textStorage.setAttributes(baseAttributes, range: total)
        for run in runs {
            let valid = NSRange(
                location: max(0, min(run.range.location, total.length)),
                length: max(0, min(run.range.length, total.length - run.range.location))
            )
            guard valid.length > 0 else { continue }
            let typedAttrs = run.attributes.reduce(into: [NSAttributedString.Key: Any]()) { acc, kv in
                acc[kv.key] = kv.value
            }
            textStorage.addAttributes(typedAttrs, range: valid)
        }
        applyBulletAttachments(in: total, source: source)
        textStorage.endEditing()
    }

    /// Substitutes each `-` / `*` / `+` list marker with a rendered bullet
    /// glyph that varies by nesting level (• ◦ ▪ ▫ cycling), so the text
    /// reads as a real bulleted list rather than ASCII source. The
    /// underlying source character is unchanged — only its display.
    private func applyBulletAttachments(in total: NSRange, source: String) {
        let pattern = #"^([ \t]*)([-*+])(?=[ \t])"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        ) else { return }
        let ns = source as NSString
        let matches = regex.matches(in: source, options: [], range: total)
        let cfFont = theme.bodyFont as CTFont
        for match in matches {
            let leadingRange = match.range(at: 1)
            let markerRange = match.range(at: 2)
            guard markerRange.location != NSNotFound else { continue }
            let leading = leadingRange.location == NSNotFound
                ? ""
                : ns.substring(with: leadingRange)
            let level = BulletAttachment.level(forLeading: leading)
            let glyphString = BulletAttachment.glyph(forLevel: level)
            let nsGlyph = glyphString as NSString
            var bulletChars: [unichar] = []
            for i in 0..<nsGlyph.length { bulletChars.append(nsGlyph.character(at: i)) }
            var cgGlyphs = [CGGlyph](repeating: 0, count: bulletChars.count)
            guard CTFontGetGlyphsForCharacters(cfFont, bulletChars, &cgGlyphs, bulletChars.count) else { continue }
            let baseChar = ns.substring(with: markerRange) as CFString
            guard let info = CTGlyphInfoCreateWithGlyph(cgGlyphs[0], cfFont, baseChar) else { continue }
            textStorage.addAttribute(.glyphInfoCompat, value: info, range: markerRange)
            textStorage.addAttribute(.font, value: theme.bodyFont, range: markerRange)
        }
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: theme.bodyFont,
            .foregroundColor: theme.foregroundColor
        ]
    }

    private func recomputeHidden() {
        hiddenRanges = HiddenRangeComputer.hiddenRanges(
            markupRanges: markupRanges,
            cursorRange: selection,
            in: textStorage.string
        )
    }
}

