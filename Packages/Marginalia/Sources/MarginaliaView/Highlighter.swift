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

    /// Compute highlight runs for the given source text.
    public func runs(for source: String) -> [Run] {
        guard let tree = parser.parse(source), let root = tree.rootNode else { return [] }
        let mapping = parser.mapping
        var spans = applier.highlights(rootNode: root, in: tree, mapping: mapping, grammar: .block)

        // Inline parse — run inline grammar over the full source. The block
        // grammar emits `inline` nodes whose contents the inline grammar parses;
        // a full-source inline pass produces correct spans for emphasis, links,
        // code spans, etc. (Mismatched matches outside `inline` regions are
        // fine — the block grammar's spans take precedence visually.)
        if let inlineTree = inlineParser.parse(source), let inlineRoot = inlineTree.rootNode {
            let inlineSpans = applier.highlights(
                rootNode: inlineRoot,
                in: inlineTree,
                mapping: inlineParser.mapping,
                grammar: .inline
            )
            spans.append(contentsOf: inlineSpans)
        }

        if dialect == .remarkup {
            spans.append(contentsOf: RemarkupGrammar.highlights(in: source))
        }

        return spans.compactMap { span in
            let attrs = attributes(for: span.tag)
            guard !attrs.isEmpty else { return nil }
            return Run(range: span.range, attributes: attrs)
        }
    }

    /// Compute the markup-character ranges that should be hidden when the
    /// cursor is *not* on those lines (caret-aware focus mode).
    public func markupRanges(for source: String) -> [NSRange] {
        runs(for: source).filter { isMarkupRun($0) }.map(\.range)
    }

    private func isMarkupRun(_ run: Run) -> Bool {
        guard let color = run.attributes[.foregroundColor] as? PlatformColor else { return false }
        return color == theme.markupColor
    }

    private func attributes(for tag: HighlightTag) -> [NSAttributedString.Key: AnyHashable] {
        switch tag {
        case .textTitle:
            return [
                .font: italicizedOrBold(theme.bodyFont, scale: 1.4, bold: true),
                .foregroundColor: theme.foregroundColor
            ]
        case .textStrong:
            return [.font: italicizedOrBold(theme.bodyFont, bold: true)]
        case .textEmphasis:
            return [.font: italicizedOrBold(theme.bodyFont, italic: true)]
        case .textLiteral:
            return [
                .font: theme.monospaceFont,
                .backgroundColor: theme.codeBackground
            ]
        case .textURI, .textReference:
            return [.foregroundColor: theme.linkColor]
        case .punctuationSpecial, .punctuationDelimiter, .stringEscape:
            return [.foregroundColor: theme.markupColor]
        case .none, .unknown:
            return [:]
        }
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
