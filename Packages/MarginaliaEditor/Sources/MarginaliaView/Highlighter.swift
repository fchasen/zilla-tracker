import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Pure transform: source text → list of `(NSRange, NSAttributedString.Key: Any)`
/// pairs that the editor's `StorageDelegate` applies in a single batch.
///
/// Doesn't touch any UI types — fully testable without TextKit / a window.
public final class Highlighter {
    public enum Dialect: Sendable {
        case commonMark
        case remarkup
    }

    public struct Run: Equatable {
        public let range: NSRange
        public let attributes: [NSAttributedString.Key: AnyHashable]

        public init(range: NSRange, attributes: [NSAttributedString.Key: AnyHashable]) {
            self.range = range
            self.attributes = attributes
        }

        public static func == (lhs: Run, rhs: Run) -> Bool {
            lhs.range == rhs.range && lhs.attributes == rhs.attributes
        }
    }

    public let theme: MarginaliaTheme
    public let dialect: Dialect
    private let parser: MarkdownParser
    private let inlineParser: MarkdownParser
    private let applier: HighlightApplier

    public init(dialect: Dialect, theme: MarginaliaTheme = .default) throws {
        self.theme = theme
        self.dialect = dialect
        self.parser = try MarkdownParser(grammar: .block)
        self.inlineParser = try MarkdownParser(grammar: .inline)
        self.applier = try HighlightApplier()
    }

    /// Combined output of one block-grammar + one inline-grammar parse.
    /// Callers that need more than one of these slices should prefer
    /// `analyze(_:blockRegions:)` over invoking `runs`, `markupRanges`, and
    /// `inlineRegions` separately — each of those triggers its own pair of
    /// parses, which is wasteful per refresh.
    public struct Analysis {
        public let runs: [Run]
        public let markupRanges: [NSRange]
        public let inlineRegions: [InlineRegion]
    }

    public func analyze(_ source: String, blockRegions: [BlockRegion] = []) -> Analysis {
        let blockSpans = parseBlockSpans(for: source)
        let (inlineSpans, inlineRegions) = parseInlineSpansAndRegions(for: source)
        var spans = blockSpans
        spans.append(contentsOf: inlineSpans)
        if dialect == .remarkup {
            spans.append(contentsOf: RemarkupGrammar.highlights(in: source))
        }

        let runs: [Run] = spans.compactMap { span in
            let attrs = attributes(for: span.tag, in: span.range, blockRegions: blockRegions)
            guard !attrs.isEmpty else { return nil }
            return Run(range: span.range, attributes: attrs)
        }

        let rawMarkup = spans.compactMap { Highlighter.isMarkupTag($0.tag) ? $0.range : nil }
        let markup = Highlighter.extendBlockPrefixMarkup(rawMarkup, in: source)

        return Analysis(runs: runs, markupRanges: markup, inlineRegions: inlineRegions)
    }

    /// Compute highlight runs for the given source text.
    ///
    /// `blockRegions`, if provided, lets the highlighter look up the heading
    /// level for each `text.title` span so H1 gets a bigger font than H2,
    /// etc. When empty, the textTitle attributes fall back to the H2 scale.
    public func runs(for source: String, blockRegions: [BlockRegion] = []) -> [Run] {
        analyze(source, blockRegions: blockRegions).runs
    }

    /// Compute the markup-character ranges that should be hidden when the
    /// cursor is *not* on those lines (caret-aware focus mode). Markup is
    /// determined by tag (`punctuation.special`, `punctuation.delimiter`,
    /// `string.escape`), not by the resulting foreground color — the latter
    /// is fragile if a theme changes its `markupColor`.
    public func markupRanges(for source: String, blockRegions: [BlockRegion] = []) -> [NSRange] {
        analyze(source, blockRegions: blockRegions).markupRanges
    }

    private func parseBlockSpans(for source: String) -> [HighlightSpan] {
        guard let tree = parser.parse(source), let root = tree.rootNode else { return [] }
        return applier.highlights(rootNode: root, in: tree, mapping: parser.mapping, grammar: .block)
    }

    /// Inline parse — run inline grammar over the full source. The block
    /// grammar emits `inline` nodes whose contents the inline grammar parses;
    /// a full-source inline pass produces correct spans for emphasis, links,
    /// code spans, etc. (Mismatched matches outside `inline` regions are
    /// fine — the block grammar's spans take precedence visually.)
    private func parseInlineSpansAndRegions(for source: String) -> (spans: [HighlightSpan], regions: [InlineRegion]) {
        guard let tree = inlineParser.parse(source), let root = tree.rootNode else {
            return ([], [])
        }
        let spans = applier.highlights(
            rootNode: root,
            in: tree,
            mapping: inlineParser.mapping,
            grammar: .inline
        )
        let regions = InlineClassifier.classify(rootNode: root, mapping: inlineParser.mapping)
        return (spans, regions)
    }

    private static func isMarkupTag(_ tag: HighlightTag) -> Bool {
        switch tag {
        case .punctuationSpecial, .punctuationDelimiter, .stringEscape:
            return true
        default:
            return false
        }
    }

    /// `#` heading and `>` blockquote markers hide along with their trailing
    /// whitespace so the body text reads flush-left when the caret is off the
    /// line. List markers (`-` `*` `+` and ordered) are intentionally left
    /// unextended because their `-` swaps to a bullet glyph and we want the
    /// space between the bullet and the item text to remain visible.
    static func extendBlockPrefixMarkup(_ ranges: [NSRange], in source: String) -> [NSRange] {
        let ns = source as NSString
        return ranges.map { range in
            guard range.length > 0 else { return range }
            let firstChar = ns.character(at: range.location)
            guard firstChar == 0x23 /* # */ || firstChar == 0x3E /* > */ else { return range }
            var end = range.location + range.length
            while end < ns.length {
                let c = ns.character(at: end)
                if c == 0x20 /* space */ || c == 0x09 /* tab */ {
                    end += 1
                } else {
                    break
                }
            }
            return NSRange(location: range.location, length: end - range.location)
        }
    }

    /// Inline links and images, derived from the inline tree.
    public func inlineRegions(for source: String) -> [InlineRegion] {
        parseInlineSpansAndRegions(for: source).regions
    }

    private func attributes(
        for tag: HighlightTag,
        in range: NSRange,
        blockRegions: [BlockRegion]
    ) -> [NSAttributedString.Key: AnyHashable] {
        switch tag {
        case .textTitle:
            let level = headingLevel(at: range, in: blockRegions) ?? 2
            let scale = theme.headingScale[level] ?? 1.0
            return [
                .font: italicizedOrBold(theme.bodyFont, scale: scale, bold: true),
                .foregroundColor: theme.foregroundColor
            ]
        case .textStrong:
            let scale = headingScale(at: range, in: blockRegions)
            return [.font: italicizedOrBold(theme.bodyFont, scale: scale, bold: true)]
        case .textEmphasis:
            let scale = headingScale(at: range, in: blockRegions)
            return [.font: italicizedOrBold(theme.bodyFont, scale: scale, italic: true)]
        case .textLiteral:
            return [.font: theme.monospaceFont]
        case .textURI:
            // The URL portion of a markdown link — render dimmed so the
            // bracket text reads as the actual hyperlink label.
            return [.foregroundColor: theme.linkURLColor]
        case .textReference:
            return [.foregroundColor: theme.linkColor]
        case .punctuationSpecial, .punctuationDelimiter, .stringEscape:
            return [.foregroundColor: theme.markupColor]
        case .none, .unknown:
            return [:]
        }
    }

    private func headingLevel(at range: NSRange, in blockRegions: [BlockRegion]) -> Int? {
        for region in blockRegions {
            guard region.range.contains(range.location)
                || (range.location == region.range.upperBound && range.length == 0) else { continue }
            switch region.kind {
            case .heading(let level): return level
            case .setextHeading(let level): return level
            default: continue
            }
        }
        return nil
    }

    private func headingScale(at range: NSRange, in blockRegions: [BlockRegion]) -> CGFloat {
        guard let level = headingLevel(at: range, in: blockRegions) else { return 1.0 }
        return theme.headingScale[level] ?? 1.0
    }

    private func italicizedOrBold(
        _ base: PlatformFont,
        scale: CGFloat = 1.0,
        bold: Bool = false,
        italic: Bool = false
    ) -> PlatformFont {
        let pointSize = base.pointSize * scale
        #if canImport(AppKit) && os(macOS)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? base
        #else
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
        #endif
    }
}
