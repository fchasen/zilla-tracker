import Testing
import Foundation
import SwiftTreeSitter
@testable import MarginaliaSyntax

@Suite(.serialized) struct ParserFragilityTests {

    @Test func applyEditFromEmptyTreeReturnsConsistentByteRange() throws {
        let p = try MarkdownParser(grammar: .block)
        let ranges = p.applyEdit(
            replacing: NSRange(location: 0, length: 0),
            with: "café",
            newSource: "café"
        )
        try #require(ranges.count == 1)
        let expected = TreeSitterMapping(text: "café").byteOffset(forUTF16: 4)
        #expect(ranges[0].bytes.upperBound == expected)
    }

    @Test func applyEditAfterEditsMatchesFromScratchParse() throws {
        let p = try MarkdownParser(grammar: .block)
        p.parse("hello")
        p.applyEdit(
            replacing: NSRange(location: 5, length: 0),
            with: " world",
            newSource: "hello world"
        )
        p.applyEdit(
            replacing: NSRange(location: 0, length: 0),
            with: "# ",
            newSource: "# hello world"
        )
        p.applyEdit(
            replacing: NSRange(location: 13, length: 0),
            with: "\n\nparagraph",
            newSource: "# hello world\n\nparagraph"
        )

        let fresh = try MarkdownParser(grammar: .block)
        fresh.parse("# hello world\n\nparagraph")

        let incremental = try #require(p.rootNode?.sExpressionString)
        let fromScratch = try #require(fresh.rootNode?.sExpressionString)
        #expect(incremental == fromScratch)
    }

    @Test func applyEditAcrossEmojiSurrogatePairKeepsParseStable() throws {
        let p = try MarkdownParser(grammar: .block)
        p.parse("hello 🚀 world")
        p.applyEdit(
            replacing: NSRange(location: 6, length: 2),
            with: "X",
            newSource: "hello X world"
        )
        let fresh = try MarkdownParser(grammar: .block)
        fresh.parse("hello X world")
        let incremental = try #require(p.rootNode?.sExpressionString)
        let fromScratch = try #require(fresh.rootNode?.sExpressionString)
        #expect(incremental == fromScratch)
    }
}

@Suite(.serialized) struct ParserIncrementalSequenceTests {

    @Test func threeIncrementalEditsAfterEmptyParseDoNotCrash() throws {
        let p = try MarkdownParser(grammar: .block)
        p.parse("")
        p.applyEdit(replacing: NSRange(location: 0, length: 0), with: "hello", newSource: "hello")
        p.applyEdit(replacing: NSRange(location: 5, length: 0), with: " world", newSource: "hello world")
        p.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ", newSource: "# hello world")
        let s = try #require(p.rootNode?.sExpressionString)
        #expect(s.contains("atx_heading"))
    }
}

struct EditingOpsFragilityTests {

    @Test func switchListMarkerBulletToNumberedRenumbersFromOne() {
        let result = EditingOps.switchListMarker(
            in: "- a\n- b\n- c",
            selection: NSRange(location: 0, length: 11),
            to: .numbered
        )
        try? #require(result != nil)
        #expect(result?.text == "1. a\n2. b\n3. c")
    }

    @Test func switchListMarkerNumberedToTaskPreservesIndent() {
        let result = EditingOps.switchListMarker(
            in: "  1. one\n  2. two",
            selection: NSRange(location: 0, length: 17),
            to: .task
        )
        try? #require(result != nil)
        #expect(result?.text == "  - [ ] one\n  - [ ] two")
    }

    @Test func switchListMarkerNumberedToBullet() {
        let result = EditingOps.switchListMarker(
            in: "1. one\n2. two",
            selection: NSRange(location: 0, length: 13),
            to: .bullet
        )
        #expect(result?.text == "- one\n- two")
    }

    @Test func wrapCodeBlockAfterEmojiInsertsLeadingNewline() {
        let result = EditingOps.wrapCodeBlock(
            in: "🚀",
            selection: NSRange(location: 2, length: 0),
            placeholder: "code"
        )
        #expect(result.text.hasPrefix("🚀\n```\n"))
    }

    @Test func horizontalRuleAfterEmojiAtEndOfTextInsertsLeadingNewline() {
        let result = EditingOps.insertHorizontalRule(
            in: "🚀",
            selection: NSRange(location: 2, length: 0)
        )
        #expect(result.text == "🚀\n---\n\n")
    }

    @Test func horizontalRuleAtStartOfBufferOmitsLeadingNewline() {
        let result = EditingOps.insertHorizontalRule(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )
        #expect(result.text == "---\n\n")
    }
}

struct ListContinuationFragilityTests {

    @Test func returnInsideBlockquoteContinuesQuoteMarker() {
        let result = ListContinuation.handleReturn(in: "> hello", cursor: 7)
        #expect(result?.text == "> hello\n> ")
    }

    @Test func returnInsideIndentedNumberedListIncrements() {
        let result = ListContinuation.handleReturn(in: "  1. one", cursor: 8)
        #expect(result?.text == "  1. one\n  2. ")
    }

    @Test func returnAtEmptyTaskListItemTerminatesList() {
        let result = ListContinuation.handleReturn(in: "- [ ] ", cursor: 6)
        #expect(result?.text == "")
        #expect(result?.selection.location == 0)
    }

    @Test func returnInBulletListAfterEmojiContent() {
        let result = ListContinuation.handleReturn(in: "- 🚀 launch", cursor: 11)
        #expect(result?.text == "- 🚀 launch\n- ")
    }
}

@Suite(.serialized) struct HighlightFragilityTests {

    private func block(_ source: String) throws -> [HighlightSpan] {
        let p = try MarkdownParser(grammar: .block)
        let tree = try #require(p.parse(source))
        let root = try #require(tree.rootNode)
        let applier = try HighlightApplier()
        return applier.highlights(rootNode: root, in: tree, mapping: p.mapping, grammar: .block)
    }

    private func inline(_ source: String) throws -> [HighlightSpan] {
        let p = try MarkdownParser(grammar: .inline)
        let tree = try #require(p.parse(source))
        let root = try #require(tree.rootNode)
        let applier = try HighlightApplier()
        return applier.highlights(rootNode: root, in: tree, mapping: p.mapping, grammar: .inline)
    }

    @Test func boldSpanCoversEmojiContentWithoutSplittingSurrogate() throws {
        let spans = try inline("**🚀 launch**")
        let strong = try #require(spans.first { $0.tag == .textStrong })
        let ns = "**🚀 launch**" as NSString
        #expect(strong.range.location == 0)
        #expect(strong.range.location + strong.range.length == ns.length)
    }

    @Test func headingFollowedByListProducesDistinctTitleAndMarkers() throws {
        let spans = try block("# heading\n- a\n- b\n")
        #expect(spans.contains { $0.tag == .textTitle })
        let punctuation = spans.filter { $0.tag == .punctuationSpecial }
        #expect(punctuation.count >= 3)
    }

    @Test func codeBlockSpansCoverFenceAndContentRanges() throws {
        let spans = try block("```\nlet x = 1\n```\n")
        #expect(spans.contains { $0.tag == .textLiteral })
        #expect(spans.contains { $0.tag == .punctuationDelimiter })
    }
}
