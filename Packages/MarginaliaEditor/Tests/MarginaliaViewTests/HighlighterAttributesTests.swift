#if canImport(AppKit) && os(macOS)
import Testing
import AppKit
import MarginaliaSyntax
@testable import MarginaliaView

/// Visual-attribute regression tests for `Highlighter`. The catalog of
/// behaviors here:
/// - heading levels scale font size (H1 > H2 > H3 …)
/// - the URL portion of a markdown link gets a dimmer color than the
///   bracket-label portion
/// - markup punctuation (`#`, `**`, etc.) gets the theme's markup color
@Suite(.serialized) struct HighlighterAttributesTests {

    private func runs(for source: String) throws -> [Highlighter.Run] {
        let parser = try MarkdownParser(grammar: .block)
        let tree = try #require(parser.parse(source))
        let root = try #require(tree.rootNode)
        let blockRegions = BlockClassifier.classify(rootNode: root, mapping: parser.mapping)
        let highlighter = try Highlighter(dialect: .commonMark)
        return highlighter.runs(for: source, blockRegions: blockRegions)
    }

    private func titleRun(for source: String) throws -> Highlighter.Run? {
        try runs(for: source).first { run in
            guard let color = run.attributes[.foregroundColor] as? NSColor else { return false }
            return color == MarginaliaTheme.default.foregroundColor
        }
    }

    // MARK: - heading sizing

    @Test func h1IsLargerThanH2() throws {
        let h1Font = try #require(try titleRun(for: "# heading\n")?.attributes[.font] as? NSFont)
        let h2Font = try #require(try titleRun(for: "## heading\n")?.attributes[.font] as? NSFont)
        #expect(h1Font.pointSize > h2Font.pointSize)
    }

    @Test func h2IsLargerThanH3() throws {
        let h2 = try #require(try titleRun(for: "## heading\n")?.attributes[.font] as? NSFont)
        let h3 = try #require(try titleRun(for: "### heading\n")?.attributes[.font] as? NSFont)
        #expect(h2.pointSize > h3.pointSize)
    }

    @Test func h1MatchesThemeScale() throws {
        let font = try #require(try titleRun(for: "# heading\n")?.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[1] ?? 1.0)
        #expect(abs(font.pointSize - expected) < 0.01)
    }

    @Test func h6MatchesThemeScale() throws {
        let font = try #require(try titleRun(for: "###### heading\n")?.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[6] ?? 1.0)
        #expect(abs(font.pointSize - expected) < 0.01)
    }

    // MARK: - link colors

    @Test func linkBracketAndURLAreDifferentColors() throws {
        let runs = try runs(for: "[label](https://example.com)")

        let refColor = runs
            .compactMap { run -> NSColor? in
                run.attributes[.foregroundColor] as? NSColor
            }
            .first { $0 == MarginaliaTheme.default.linkColor }
        let urlColor = runs
            .compactMap { run -> NSColor? in
                run.attributes[.foregroundColor] as? NSColor
            }
            .first { $0 == MarginaliaTheme.default.linkURLColor }
        #expect(refColor != nil, "Bracket label should use linkColor.")
        #expect(urlColor != nil, "URL destination should use linkURLColor.")
        #expect(MarginaliaTheme.default.linkColor != MarginaliaTheme.default.linkURLColor)
    }
}
#endif
