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
///
/// `sourceStorage` is the canonical markdown the host owns; `textStorage`
/// is what the layout manager renders. They're kept in lockstep here (1:1
/// mapping); a future display transform diverges them so the editor can
/// elide markup syntax in WYSIWYG mode.
public final class EditorController {

    public let sourceStorage: NSTextStorage
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
    public var mode: MarginaliaMode = .wysiwyg {
        didSet { refresh() }
    }

    /// Most recent block-level classification, computed alongside highlights.
    public private(set) var blockRegions: [BlockRegion] = []

    /// Markup ranges (e.g. `**`, `#`, `>`) that should be visually hidden when
    /// the cursor is *not* on those lines (caret-aware focus mode).
    public private(set) var markupRanges: [NSRange] = []

    public var selection: NSRange = NSRange(location: 0, length: 0) {
        didSet { onSelectionChanged(from: oldValue) }
    }

    public private(set) var hiddenRanges: [NSRange] = []

    /// Inline links and images parsed from the current source. Surfaced for
    /// callers (e.g. future click-to-open routing, chip rendering); the
    /// editor does not modify storage based on them yet.
    public private(set) var inlineRegions: [InlineRegion] = []

    /// Translation between the markdown source and the rendered display
    /// string. Identity in `.source` mode; elides markup syntax in
    /// `.wysiwyg` mode.
    public private(set) var displayMapping: SourceDisplayMapping = .identity(for: "")

    /// The platform text view backed by `textContainer`. Held weakly so the
    /// view can be torn down by SwiftUI without leaking; set by the
    /// `MarginaliaTextView*` representables in `make…View`. The toolbar's
    /// `applyEdit` path uses this to push the new selection back into the
    /// view after replacing storage.
    public weak var hostTextView: AnyObject?

    /// The undo manager all source mutations register inverses on. Vended to
    /// the host text view via the `undoManager(for:)` delegate hook so Cmd-Z
    /// goes through us rather than recording display-coord edits that don't
    /// round-trip through the source/display mapping.
    ///
    /// `groupsByEvent` is off so each `mutateSource` call is its own undo
    /// step — matches how typed characters are recorded in the source via
    /// `applyDisplayEditToSource`, one per keystroke. Future enhancement:
    /// coalesce consecutive single-char inserts into typing groups (the
    /// default NSTextView behavior we lost when we disabled `allowsUndo`).
    public let undoManager: UndoManager = {
        let m = UndoManager()
        m.groupsByEvent = false
        return m
    }()

    /// Hook the representable installs so storage edits invalidate the
    /// host view's intrinsic content size — that's how the editor grows
    /// with its content in `EditorSizing.fitsContent` mode.
    public var intrinsicSizeInvalidator: (() -> Void)?

    private var highlighter: Highlighter
    private let parser: MarkdownParser
    private let layoutDelegate: LayoutManagerDelegate
    private var refreshing = false
    private var storageObserver: NSObjectProtocol?
    /// Set while we're mirroring source ↔ display so the storage observer
    /// doesn't bounce the same edit back through the sync.
    private var syncing = false

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

        self.sourceStorage = NSTextStorage(string: initialText)
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
            guard let self, !self.syncing else { return }
            // Only re-parse on character edits — attribute-only edits
            // (notably the focus-mode hide pass below) would otherwise drag
            // a full reparse along on every cursor move.
            // `applyDisplayEditToSource` runs through `mutateSource`, which
            // already calls `scheduleRefresh` — no need to schedule again.
            if self.textStorage.editedMask.contains(.editedCharacters) {
                self.applyDisplayEditToSource()
            }
            self.intrinsicSizeInvalidator?()
        }

        refresh()
    }

    deinit {
        if let storageObserver {
            NotificationCenter.default.removeObserver(storageObserver)
        }
    }

    /// Replace the entire text. Triggers a full re-parse + re-highlight and
    /// registers an inverse on `undoManager` so Cmd-Z restores the prior text.
    public func setText(_ text: String) {
        let sourceRange = NSRange(location: 0, length: sourceStorage.length)
        mutateSource(replacing: sourceRange, with: text)
    }

    public var text: String {
        get { sourceStorage.string }
        set { setText(newValue) }
    }

    /// Apply a single edit in source coordinates. Caller is responsible for
    /// ensuring the edit's NSRange is valid against the current `text`.
    public func applyEdit(replacing range: NSRange, with replacement: String) {
        mutateSource(replacing: range, with: replacement)
    }

    /// The single funnel for source mutations. Captures the inverse and
    /// registers it on `undoManager` so undo replays the inverse, and so an
    /// undo-during-an-undo (= redo) registers the *original* edit. The
    /// `syncing` flag prevents the storage observer from re-mirroring the
    /// just-applied edit back through the source/display sync.
    @discardableResult
    private func mutateSource(replacing range: NSRange, with replacement: String) -> NSRange {
        let ns = sourceStorage.string as NSString
        let safe = NSRange(
            location: max(0, min(range.location, ns.length)),
            length: max(0, min(range.length, ns.length - max(0, min(range.location, ns.length))))
        )
        let oldText = ns.substring(with: safe)
        syncing = true
        sourceStorage.replaceCharacters(in: safe, with: replacement)
        syncing = false
        let newRange = NSRange(location: safe.location, length: (replacement as NSString).length)
        // `groupsByEvent` is off, so every registration has to live inside
        // an explicit grouping pair — one mutation = one undo step.
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { controller in
            controller.mutateSource(replacing: newRange, with: oldText)
        }
        undoManager.endUndoGrouping()
        scheduleRefresh()
        return newRange
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
        let clampedSource = NSRange(
            location: location,
            length: max(0, min(result.selection.length, remaining))
        )
        setText(result.text)
        // Clamp the cached selection BEFORE refreshing — `recomputeHidden`
        // (called inside `refreshNow`) reads `self.selection` and would
        // crash on `lineRange(for:)` if it's still pointing into the old,
        // longer text.
        selection = clampedSource
        // Apply highlights + paragraph styles synchronously so the freshly
        // inserted text doesn't render unstyled for one frame. Without this,
        // a newly continued list line is rendered without its hanging-indent
        // paragraph style until the next runloop tick.
        refreshNow()
        // Translate to display coords for the text view — `clampedSource`
        // is a source range, the text view lives in display.
        let clampedDisplay = displayMapping.displayRange(forSource: clampedSource)
        let displayLength = textStorage.length
        let displayLocation = max(0, min(clampedDisplay.location, displayLength))
        let displayRemaining = max(0, displayLength - displayLocation)
        let viewRange = NSRange(
            location: displayLocation,
            length: max(0, min(clampedDisplay.length, displayRemaining))
        )
        #if canImport(AppKit) && os(macOS)
        if let tv = hostTextView as? NSTextView {
            tv.setSelectedRange(viewRange)
        }
        #elseif canImport(UIKit)
        if let tv = hostTextView as? UITextView {
            tv.selectedRange = viewRange
        }
        #endif
    }

    /// Clamps `range` to the current text's bounds, useful when the toolbar
    /// receives a stale selection (e.g. from a `.constant` SwiftUI binding)
    /// and needs to defend against `NSRangeException` in `EditingOps`.
    public func clampedRange(_ range: NSRange) -> NSRange {
        let length = sourceStorage.length
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
        let source = sourceStorage.string

        if let tree = parser.parse(source), let root = tree.rootNode {
            blockRegions = BlockClassifier.classify(rootNode: root, mapping: parser.mapping)
        } else {
            blockRegions = []
        }

        let analysis = highlighter.analyze(source, blockRegions: blockRegions)
        markupRanges = analysis.markupRanges
        inlineRegions = analysis.inlineRegions

        let newMapping = computeMapping(for: source)
        rebuildDisplayIfNeeded(with: newMapping)

        applyAttributes(runs: analysis.runs, full: source)
        applyImageAttachmentChips()
        applyTaskCheckboxAttachments(in: source)
        recomputeHidden()
    }

    private func applyImageAttachmentChips() {
        for region in inlineRegions {
            guard case let .image(_, alt) = region.kind else { continue }
            let displayRange = displayMapping.displayRange(forSource: region.range)
            // Only attach when the substitution actually inserted a single
            // `￼` character — in source mode there's no substitution.
            guard displayRange.length == 1 else { continue }
            let attachment = ChipTextAttachment()
            attachment.chipLabel = alt.isEmpty ? "image" : alt
            attachment.chipSymbol = "photo"
            textStorage.addAttribute(.attachment, value: attachment, range: displayRange)
        }
    }

    private func applyTaskCheckboxAttachments(in source: String) {
        for match in checkboxSubstitutions(in: source) {
            let displayRange = displayMapping.displayRange(forSource: match.bracketRange)
            // Substitution kicked in only if the active-line filter didn't
            // veto it; otherwise the bracket is verbatim and we leave it
            // alone (the user is editing this line directly).
            guard displayRange.length == 1 else { continue }
            let attachment = CheckboxAttachment()
            attachment.isChecked = match.isChecked
            textStorage.addAttribute(.attachment, value: attachment, range: displayRange)
            if let url = EditorController.taskToggleURL(forSourceLocation: match.bracketRange.location) {
                textStorage.addAttribute(.link, value: url, range: displayRange)
            }
        }
    }

    /// Builds the URL we attach to a checkbox glyph so a click can be routed
    /// back to the correct source position via `toggleTask(atSourceLocation:)`.
    public static func taskToggleURL(forSourceLocation location: Int) -> URL? {
        URL(string: "marginalia://task?source=\(location)")
    }

    /// Parses a URL minted by `taskToggleURL` and returns the source position
    /// of the bracket, or `nil` if the URL isn't a task-toggle URL.
    public static func taskToggleSourceLocation(from url: URL) -> Int? {
        guard url.scheme == "marginalia", url.host == "task" else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return comps?.queryItems?.first(where: { $0.name == "source" })
            .flatMap { $0.value.flatMap(Int.init) }
    }

    /// Toggles a `[ ]` ↔ `[x]` task marker at the given source bracket
    /// location. The location must point at the `[` of the bracket — the
    /// same value `taskToggleURL` was minted from.
    public func toggleTask(atSourceLocation location: Int) {
        let source = sourceStorage.string
        let ns = source as NSString
        guard location >= 0, location + 3 <= ns.length else { return }
        let bracketRange = NSRange(location: location, length: 3)
        let bracket = ns.substring(with: bracketRange)
        let next: String
        switch bracket {
        case "[ ]": next = "[x]"
        case "[x]", "[X]": next = "[ ]"
        default: return
        }
        let result = EditResult(
            text: ns.replacingCharacters(in: bracketRange, with: next),
            selection: NSRange(location: location + 3, length: 0)
        )
        applyEdit(result)
    }

    private func computeMapping(for source: String) -> SourceDisplayMapping {
        let subs: [DisplaySubstitution]
        switch mode {
        case .source:
            // Source mode: only checkbox glyph substitution applies; markup
            // is left visible.
            subs = checkboxSubstitutions(in: source).map { match in
                DisplaySubstitution(sourceRange: match.bracketRange, displayString: "\u{FFFC}")
            }
        case .wysiwyg:
            subs = wysiwygSubstitutions(for: source)
        }
        return DisplayTransform.transform(source: source, substitutions: subs)
    }

    private func wysiwygSubstitutions(for source: String) -> [DisplaySubstitution] {
        let imageRanges = inlineRegions.compactMap { region -> NSRange? in
            if case .image = region.kind { return region.range }
            return nil
        }
        let checkboxes = checkboxSubstitutions(in: source)
        var subs: [DisplaySubstitution] = []
        // Image chips first — the whole `![alt](url)` source range collapses
        // to a single `￼` placeholder; the attachment is attached after the
        // mapping runs in `applyImageAttachmentChips`.
        for range in imageRanges {
            subs.append(DisplaySubstitution(sourceRange: range, displayString: "\u{FFFC}"))
        }
        // Task list lines: elide the bullet marker so only the checkbox
        // shows in display, and substitute the bracket with a `￼` that
        // `applyTaskCheckboxAttachments` will render as a real checkbox.
        for match in checkboxes {
            subs.append(DisplaySubstitution.elide(match.bulletRange))
            subs.append(DisplaySubstitution(sourceRange: match.bracketRange, displayString: "\u{FFFC}"))
        }
        // Markup elides — skip any range that falls inside an image (the
        // image substitution covers it already).
        let elides = wysiwygElideRanges(for: source).filter { range in
            !imageRanges.contains(where: { $0.contains(range.location) })
        }
        subs.append(contentsOf: elides.map(DisplaySubstitution.elide))

        // Reveal the active line so the user sees the raw markdown they're
        // editing — substitutions on lines they aren't on stay collapsed.
        let activeLine = activeLineSourceRange(in: source)
        return subs.filter { sub in
            !rangesIntersect(sub.sourceRange, activeLine)
        }
    }

    private func activeLineSourceRange(in source: String) -> NSRange {
        let ns = source as NSString
        return ns.lineRange(for: selection.clamped(to: ns.length))
    }

    private func rangesIntersect(_ a: NSRange, _ b: NSRange) -> Bool {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        return a.location < bEnd && b.location < aEnd
    }

    struct CheckboxMatch {
        let bulletRange: NSRange
        let bracketRange: NSRange
        let isChecked: Bool
    }

    private func checkboxSubstitutions(in source: String) -> [CheckboxMatch] {
        let pattern = #"^[ \t]*((?:[-*+]|\d+[.)])\s+)(\[([ xX])\])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let total = NSRange(location: 0, length: (source as NSString).length)
        let ns = source as NSString
        return regex.matches(in: source, options: [], range: total).compactMap { match in
            let bullet = match.range(at: 1)
            let bracket = match.range(at: 2)
            let inside = match.range(at: 3)
            guard bullet.location != NSNotFound,
                  bracket.location != NSNotFound,
                  inside.location != NSNotFound else { return nil }
            let insideChar = ns.substring(with: inside)
            return CheckboxMatch(
                bulletRange: bullet,
                bracketRange: bracket,
                isChecked: insideChar.lowercased() == "x"
            )
        }
    }

    /// In WYSIWYG mode, every markup range from the highlighter is a candidate
    /// for elision *except* list markers (which become bullets via glyph
    /// substitution) and thematic breaks (which the layout fragment paints).
    private func wysiwygElideRanges(for source: String) -> [NSRange] {
        let listMarkerLocations = listMarkerStartLocations(in: source)
        let horizontalRuleRanges: [NSRange] = blockRegions.compactMap { region in
            if case .horizontalRule = region.kind { return region.range }
            return nil
        }
        let ns = source as NSString
        return markupRanges.filter { range in
            if listMarkerLocations.contains(range.location) {
                return false
            }
            if horizontalRuleRanges.contains(where: { $0.contains(range.location) }) {
                return false
            }
            // `block_continuation` and similar all-whitespace markup tokens
            // tag the leading indent that signals list nesting; eliding them
            // would collapse `  - nested` to `- nested` and lose structure.
            let content = ns.substring(with: range)
            if content.allSatisfy({ $0.isWhitespace }) {
                return false
            }
            return true
        }
    }

    /// Source offsets where list markers begin (unordered or ordered). Used
    /// to keep list-marker tokens visible in WYSIWYG mode — tree-sitter's
    /// marker tokens span the marker char *plus the trailing space*, but
    /// we want the whole token kept so the bullet glyph substitution and
    /// the space-after-bullet remain in display.
    private func listMarkerStartLocations(in source: String) -> Set<Int> {
        let pattern = #"^([ \t]*)((?:[-*+])|(?:\d+[.\)]))(?=[ \t])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let total = NSRange(location: 0, length: (source as NSString).length)
        return Set(regex.matches(in: source, options: [], range: total).map { match in
            match.range(at: 2).location
        })
    }

    private func rebuildDisplayIfNeeded(with newMapping: SourceDisplayMapping) {
        guard textStorage.string != newMapping.displayString else {
            // No display change but the new mapping still has to win — the
            // analysis attribute pass and any subsequent translations have to
            // see the up-to-date mapping.
            displayMapping = newMapping
            return
        }
        let oldDisplaySelection = currentDisplaySelection()
        let sourceSelection = displayMapping.sourceRange(forDisplay: oldDisplaySelection)
        let newDisplaySelection = newMapping.displayRange(forSource: sourceSelection)
        syncing = true
        textStorage.replaceCharacters(
            in: NSRange(location: 0, length: textStorage.length),
            with: newMapping.displayString
        )
        syncing = false
        // Switch to the new mapping BEFORE moving the cursor — when
        // `setSelectedRange` synchronously fires `textViewDidChangeSelection`,
        // the delegate translates the new display position back through the
        // (now-current) mapping and lands on the right source position.
        displayMapping = newMapping
        setDisplaySelection(newDisplaySelection)
    }

    private func currentDisplaySelection() -> NSRange {
        #if canImport(AppKit) && os(macOS)
        if let tv = hostTextView as? NSTextView {
            return tv.selectedRange()
        }
        #elseif canImport(UIKit)
        if let tv = hostTextView as? UITextView {
            return tv.selectedRange
        }
        #endif
        return selection
    }

    private func setDisplaySelection(_ range: NSRange) {
        let length = textStorage.length
        let location = max(0, min(range.location, length))
        let remaining = max(0, length - location)
        let clamped = NSRange(
            location: location,
            length: max(0, min(range.length, remaining))
        )
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

    /// The text view edits `textStorage` (display); we receive the edit via
    /// the storage observer and translate it back to source coordinates
    /// using the *current* (pre-edit) mapping. The next `runRefresh` rebuilds
    /// the mapping for the new source.
    private func applyDisplayEditToSource() {
        let editedDisplayRange = textStorage.editedRange
        let changeInLength = textStorage.changeInLength
        let oldDisplayDeleteRange = NSRange(
            location: editedDisplayRange.location,
            length: max(0, editedDisplayRange.length - changeInLength)
        )
        let sourceDeleteRange = displayMapping.sourceRange(forDisplay: oldDisplayDeleteRange)
        let insertedText: String
        if editedDisplayRange.length > 0 {
            let ns = textStorage.string as NSString
            let safeRange = NSRange(
                location: max(0, min(editedDisplayRange.location, ns.length)),
                length: max(0, min(editedDisplayRange.length, ns.length - editedDisplayRange.location))
            )
            insertedText = ns.substring(with: safeRange)
        } else {
            insertedText = ""
        }
        mutateSource(replacing: sourceDeleteRange, with: insertedText)
    }


    private func applyAttributes(runs: [Highlighter.Run], full source: String) {
        let displayTotal = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        // Reset to base style first so removed markers don't leave stale attrs
        textStorage.setAttributes(baseAttributes, range: displayTotal)
        for run in runs {
            let displayRange = displayMapping.displayRange(forSource: run.range)
            guard displayRange.length > 0 else { continue }
            let typedAttrs = run.attributes.reduce(into: [NSAttributedString.Key: Any]()) { acc, kv in
                acc[kv.key] = kv.value
            }
            textStorage.addAttributes(typedAttrs, range: displayRange)
        }
        applyBulletAttachments(source: source)
        textStorage.endEditing()
    }

    /// Substitutes each `-` / `*` / `+` list marker with a rendered bullet
    /// glyph that varies by nesting level (• ◦ ▪ ▫ cycling), so the text
    /// reads as a real bulleted list rather than ASCII source. The marker
    /// stays in source storage; only the displayed glyph is substituted via
    /// `glyphInfoCompat` on the corresponding display character.
    private func applyBulletAttachments(source: String) {
        let pattern = #"^([ \t]*)([-*+])(?=[ \t])"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        ) else { return }
        let ns = source as NSString
        let sourceTotal = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: source, options: [], range: sourceTotal)
        let cfFont = theme.bodyFont as CTFont
        for match in matches {
            let leadingRange = match.range(at: 1)
            let markerSourceRange = match.range(at: 2)
            guard markerSourceRange.location != NSNotFound else { continue }
            let markerDisplayRange = displayMapping.displayRange(forSource: markerSourceRange)
            guard markerDisplayRange.length > 0 else { continue }
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
            let baseChar = ns.substring(with: markerSourceRange) as CFString
            guard let info = CTGlyphInfoCreateWithGlyph(cgGlyphs[0], cfFont, baseChar) else { continue }
            textStorage.addAttribute(.glyphInfoCompat, value: info, range: markerDisplayRange)
            textStorage.addAttribute(.font, value: theme.bodyFont, range: markerDisplayRange)
        }
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: theme.bodyFont,
            .foregroundColor: theme.foregroundColor
        ]
    }

    private func recomputeHidden() {
        // Phase A's tiny-font/clear-color hiding is gone — the WYSIWYG
        // display transform now elides markup at the storage level. The
        // public `hiddenRanges` is kept for API stability and reflects the
        // markup ranges currently elided from display.
        hiddenRanges = displayMapping.runs.compactMap { run in
            run.kind == .elide ? run.sourceRange : nil
        }
    }

    /// Selection moves don't usually need a re-parse, but in WYSIWYG mode
    /// the transform reveals the active line's markdown — so a line change
    /// has to rebuild the mapping.
    private func onSelectionChanged(from oldSelection: NSRange) {
        guard mode == .wysiwyg else {
            recomputeHidden()
            return
        }
        let ns = sourceStorage.string as NSString
        let oldLine = ns.lineRange(for: oldSelection.clamped(to: ns.length))
        let newLine = ns.lineRange(for: selection.clamped(to: ns.length))
        if NSEqualRanges(oldLine, newLine) {
            recomputeHidden()
        } else {
            scheduleRefresh()
        }
    }
}

