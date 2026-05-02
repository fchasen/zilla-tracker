#if canImport(AppKit) && os(macOS)
import XCTest
import AppKit
import MarginaliaSyntax
@testable import MarginaliaView

/// Visual-attribute regression tests for `Highlighter`. The catalog of
/// behaviors here:
/// - heading levels scale font size (H1 > H2 > H3 …)
/// - the URL portion of a markdown link gets a dimmer color than the
///   bracket-label portion
/// - markup punctuation (`#`, `**`, etc.) gets the theme's markup color
final class HighlighterAttributesTests: XCTestCase {

    private func runs(for source: String) throws -> [Highlighter.Run] {
        let parser = try MarkdownParser(grammar: .block)
        guard let tree = parser.parse(source), let root = tree.rootNode else {
            XCTFail("parse failed"); return []
        }
        let blockRegions = BlockClassifier.classify(rootNode: root, mapping: parser.mapping)
        let highlighter = try Highlighter(dialect: .commonMark)
        return highlighter.runs(for: source, blockRegions: blockRegions)
    }

    private func titleRun(for source: String) throws -> Highlighter.Run? {
        try runs(for: source).first { run in
            // The heading title gets bold + theme.foregroundColor — markup
            // characters get markupColor, so we filter on the foreground
            // matching the body text color.
            guard let color = run.attributes[.foregroundColor] as? NSColor else { return false }
            return color == MarginaliaTheme.default.foregroundColor
        }
    }

    // MARK: - heading sizing

    func testH1IsLargerThanH2() throws {
        let h1Font = try titleRun(for: "# heading\n")?.attributes[.font] as? NSFont
        let h2Font = try titleRun(for: "## heading\n")?.attributes[.font] as? NSFont
        XCTAssertNotNil(h1Font)
        XCTAssertNotNil(h2Font)
        XCTAssertGreaterThan(h1Font!.pointSize, h2Font!.pointSize)
    }

    func testH2IsLargerThanH3() throws {
        let h2 = try titleRun(for: "## heading\n")?.attributes[.font] as? NSFont
        let h3 = try titleRun(for: "### heading\n")?.attributes[.font] as? NSFont
        XCTAssertGreaterThan(h2!.pointSize, h3!.pointSize)
    }

    func testH1MatchesThemeScale() throws {
        let font = try XCTUnwrap(titleRun(for: "# heading\n")?.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[1] ?? 1.0)
        XCTAssertEqual(font.pointSize, expected, accuracy: 0.01)
    }

    func testH6MatchesThemeScale() throws {
        let font = try XCTUnwrap(titleRun(for: "###### heading\n")?.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[6] ?? 1.0)
        XCTAssertEqual(font.pointSize, expected, accuracy: 0.01)
    }

    // MARK: - inline emphasis inside headings

    private func runRange(_ source: String, of needle: String) -> NSRange {
        (source as NSString).range(of: needle)
    }

    func testBoldInsideH1KeepsHeadingScale() throws {
        let source = "# this is **bold** end\n"
        let runs = try runs(for: source)
        let boldRange = runRange(source, of: "**bold**")
        let strongRun = try XCTUnwrap(
            runs.first { $0.range == boldRange },
            "expected a strong run covering the **bold** span"
        )
        let strongFont = try XCTUnwrap(strongRun.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[1] ?? 1.0)
        XCTAssertEqual(strongFont.pointSize, expected, accuracy: 0.01,
                       "bold inside an H1 must inherit the H1 font scale")
    }

    func testItalicInsideH2KeepsHeadingScale() throws {
        let source = "## hi *am* there\n"
        let runs = try runs(for: source)
        let italicRange = runRange(source, of: "*am*")
        let emphasisRun = try XCTUnwrap(
            runs.first { $0.range == italicRange },
            "expected an emphasis run covering *am*"
        )
        let italicFont = try XCTUnwrap(emphasisRun.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[2] ?? 1.0)
        XCTAssertEqual(italicFont.pointSize, expected, accuracy: 0.01,
                       "italic inside an H2 must inherit the H2 font scale")
    }

    func testItalicOutsideHeadingUsesBodySize() throws {
        let source = "plain *am* line\n"
        let runs = try runs(for: source)
        let italicRange = runRange(source, of: "*am*")
        let emphasisRun = try XCTUnwrap(runs.first { $0.range == italicRange })
        let italicFont = try XCTUnwrap(emphasisRun.attributes[.font] as? NSFont)
        XCTAssertEqual(italicFont.pointSize, NSFont.systemFontSize, accuracy: 0.01,
                       "italic outside any heading must use the body font size")
    }

    // MARK: - code styling

    func testInlineCodeIsMonospaceWithNoBackground() throws {
        let runs = try runs(for: "say `hello world` plain\n")
        let inlineCode = runs.first { run in
            guard let font = run.attributes[.font] as? NSFont else { return false }
            return font.fontName.contains("Mono") || font == MarginaliaTheme.default.monospaceFont
        }
        let unwrapped = try XCTUnwrap(inlineCode, "expected an inline-code run with a monospace font")
        XCTAssertNil(unwrapped.attributes[.backgroundColor],
                     "inline code must not carry a background attribute")
    }

    func testFencedCodeBlockContentIsMonospaceWithNoBackground() throws {
        let source = "```\nlet x = 1\n```\n"
        let runs = try runs(for: source)
        let codeRuns = runs.filter { run in
            guard let font = run.attributes[.font] as? NSFont else { return false }
            return font == MarginaliaTheme.default.monospaceFont
        }
        XCTAssertFalse(codeRuns.isEmpty, "fenced code content should produce monospace runs")
        for run in codeRuns {
            XCTAssertNil(run.attributes[.backgroundColor],
                         "code block content must not carry a background attribute")
        }
    }

    // MARK: - link colors

    func testLinkBracketAndURLAreDifferentColors() throws {
        let runs = try runs(for: "[label](https://example.com)")

        // Link reference (bracket label) and link destination (URL) should
        // both get a foreground color — but different ones.
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
        XCTAssertNotNil(refColor, "Bracket label should use linkColor.")
        XCTAssertNotNil(urlColor, "URL destination should use linkURLColor.")
        XCTAssertNotEqual(MarginaliaTheme.default.linkColor, MarginaliaTheme.default.linkURLColor)
    }
}
#endif
