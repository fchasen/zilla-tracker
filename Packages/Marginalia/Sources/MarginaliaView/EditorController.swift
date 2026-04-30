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

    private var highlighter: Highlighter
    private let parser: MarkdownParser
    private let storageDelegate: StorageDelegateProxy
    private let layoutDelegate: LayoutManagerDelegate
    private var pendingRefresh = false

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

        self.storageDelegate = StorageDelegateProxy()
        self.layoutDelegate = LayoutManagerDelegate()

        textStorage.delegate = storageDelegate
        storageDelegate.onProcessed = { [weak self] in self?.scheduleRefresh() }
        layoutManager.delegate = layoutDelegate
        layoutDelegate.controller = self

        refresh()
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

    /// Apply a single edit and update the parse incrementally.
    /// Caller is responsible for ensuring the edit's NSRange is valid against
    /// the current `text`.
    public func applyEdit(replacing range: NSRange, with replacement: String) {
        let oldText = textStorage.string
        textStorage.replaceCharacters(in: range, with: replacement)
        let newText = textStorage.string
        parser.applyEdit(replacing: range, with: replacement, newSource: newText)
        _ = oldText  // (held for symmetry; future incremental path can compare)
        scheduleRefresh()
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
        guard !pendingRefresh else { return }
        pendingRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.runRefresh()
            self.pendingRefresh = false
        }
    }

    private func refresh() {
        runRefresh()
    }

    private func runRefresh() {
        let source = textStorage.string

        let runs = highlighter.runs(for: source)
        markupRanges = highlighter.markupRanges(for: source)

        if let tree = parser.parse(source), let root = tree.rootNode {
            blockRegions = BlockClassifier.classify(rootNode: root, mapping: parser.mapping)
        } else {
            blockRegions = []
        }

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
        textStorage.endEditing()
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

/// Lightweight `NSTextStorageDelegate` shim — owns no state, just relays the
/// `didProcessEditing` callback to the `EditorController`. Avoids the
/// retain-cycle that an inline closure on `NSTextStorage` would create.
final class StorageDelegateProxy: NSObject, NSTextStorageDelegate {
    var onProcessed: (() -> Void)?

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        onProcessed?()
    }
}
