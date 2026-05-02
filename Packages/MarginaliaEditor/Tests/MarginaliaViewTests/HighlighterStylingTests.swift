#if canImport(AppKit) && os(macOS)
import Testing
import AppKit
import MarginaliaSyntax
@testable import MarginaliaView

@Suite(.serialized) struct HighlighterStylingTests {

    private func runs(for source: String) throws -> [Highlighter.Run] {
        let parser = try MarkdownParser(grammar: .block)
        let tree = try #require(parser.parse(source))
        let root = try #require(tree.rootNode)
        let blockRegions = BlockClassifier.classify(rootNode: root, mapping: parser.mapping)
        let highlighter = try Highlighter(dialect: .commonMark)
        return highlighter.runs(for: source, blockRegions: blockRegions)
    }

    private func runRange(_ source: String, of needle: String) -> NSRange {
        (source as NSString).range(of: needle)
    }

    @Test func boldInsideH1KeepsHeadingScale() throws {
        let source = "# this is **bold** end\n"
        let runs = try runs(for: source)
        let strong = try #require(runs.first { $0.range == runRange(source, of: "**bold**") })
        let font = try #require(strong.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[1] ?? 1.0)
        #expect(abs(font.pointSize - expected) < 0.01)
    }

    @Test func italicInsideH2KeepsHeadingScale() throws {
        let source = "## hi *am* there\n"
        let runs = try runs(for: source)
        let emphasis = try #require(runs.first { $0.range == runRange(source, of: "*am*") })
        let font = try #require(emphasis.attributes[.font] as? NSFont)
        let expected = NSFont.systemFontSize * (MarginaliaTheme.default.headingScale[2] ?? 1.0)
        #expect(abs(font.pointSize - expected) < 0.01)
    }

    @Test func italicOutsideHeadingUsesBodySize() throws {
        let source = "plain *am* line\n"
        let runs = try runs(for: source)
        let emphasis = try #require(runs.first { $0.range == runRange(source, of: "*am*") })
        let font = try #require(emphasis.attributes[.font] as? NSFont)
        #expect(abs(font.pointSize - NSFont.systemFontSize) < 0.01)
    }

    @Test func inlineCodeIsMonospaceWithNoBackground() throws {
        let runs = try runs(for: "say `hello world` plain\n")
        let mono = MarginaliaTheme.default.monospaceFont
        let codeRun = try #require(runs.first { run in
            (run.attributes[.font] as? NSFont) == mono
        })
        #expect(codeRun.attributes[.backgroundColor] == nil)
    }

    @Test func fencedCodeBlockContentIsMonospaceWithNoBackground() throws {
        let source = "```\nlet x = 1\n```\n"
        let runs = try runs(for: source)
        let mono = MarginaliaTheme.default.monospaceFont
        let codeRuns = runs.filter { ($0.attributes[.font] as? NSFont) == mono }
        try #require(!codeRuns.isEmpty)
        for run in codeRuns {
            #expect(run.attributes[.backgroundColor] == nil)
        }
    }
}
#endif
