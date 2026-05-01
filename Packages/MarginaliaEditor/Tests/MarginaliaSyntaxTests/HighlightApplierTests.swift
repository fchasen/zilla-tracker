import XCTest
import SwiftTreeSitter
@testable import MarginaliaSyntax

final class HighlightApplierTests: XCTestCase {

    private func block(_ source: String) throws -> [HighlightSpan] {
        let p = try MarkdownParser(grammar: .block)
        guard let tree = p.parse(source), let root = tree.rootNode else {
            XCTFail("parse failed")
            return []
        }
        let applier = try HighlightApplier()
        return applier.highlights(rootNode: root, in: tree, mapping: p.mapping, grammar: .block)
    }

    private func inline(_ source: String) throws -> [HighlightSpan] {
        let p = try MarkdownParser(grammar: .inline)
        guard let tree = p.parse(source), let root = tree.rootNode else {
            XCTFail("parse failed")
            return []
        }
        let applier = try HighlightApplier()
        return applier.highlights(rootNode: root, in: tree, mapping: p.mapping, grammar: .inline)
    }

    // MARK: - block grammar

    func testHeadingMarkerAndTitle() throws {
        let spans = try block("# heading\n")
        XCTAssertTrue(spans.contains { $0.tag == .punctuationSpecial },
                      "expected '#' marker as punctuation.special: \(spans)")
        XCTAssertTrue(spans.contains { $0.tag == .textTitle },
                      "expected heading title: \(spans)")
    }

    func testHeadingTitleRangeMatchesUTF16() throws {
        let spans = try block("# h\n")
        let title = spans.first { $0.tag == .textTitle }
        XCTAssertNotNil(title)
        // "# h\n" — title text "h" lives at utf16 offset 2 length 1
        XCTAssertEqual(title?.range.location, 2)
        XCTAssertEqual(title?.range.length, 1)
    }

    func testFencedCodeBlockHighlights() throws {
        let spans = try block("```\nlet x = 1\n```\n")
        XCTAssertTrue(spans.contains { $0.tag == .textLiteral })
        XCTAssertTrue(spans.contains { $0.tag == .punctuationDelimiter })
    }

    func testListMarkers() throws {
        let spans = try block("- a\n- b\n")
        let markers = spans.filter { $0.tag == .punctuationSpecial }
        XCTAssertGreaterThanOrEqual(markers.count, 2)
    }

    func testThematicBreak() throws {
        let spans = try block("---\n")
        XCTAssertTrue(spans.contains { $0.tag == .punctuationSpecial })
    }

    func testBlockquoteMarker() throws {
        let spans = try block("> quoted\n")
        XCTAssertTrue(spans.contains { $0.tag == .punctuationSpecial })
    }

    // MARK: - inline grammar

    func testStrongEmphasis() throws {
        let spans = try inline("**bold**")
        XCTAssertTrue(spans.contains { $0.tag == .textStrong })
        XCTAssertTrue(spans.contains { $0.tag == .punctuationDelimiter })
    }

    func testEmphasis() throws {
        let spans = try inline("*italic*")
        XCTAssertTrue(spans.contains { $0.tag == .textEmphasis })
    }

    func testCodeSpan() throws {
        let spans = try inline("`code`")
        XCTAssertTrue(spans.contains { $0.tag == .textLiteral })
    }

    func testInlineLink() throws {
        let spans = try inline("[label](https://example.com)")
        XCTAssertTrue(spans.contains { $0.tag == .textURI })
        XCTAssertTrue(spans.contains { $0.tag == .textReference })
    }

    func testEmphasisRangeIncludesContent() throws {
        let spans = try inline("**bold**")
        let strongSpan = spans.first { $0.tag == .textStrong }
        XCTAssertNotNil(strongSpan)
        // strong_emphasis covers the whole "**bold**" — utf16 [0, 8)
        XCTAssertEqual(strongSpan?.range.location, 0)
        XCTAssertEqual(strongSpan?.range.length, 8)
    }
}
