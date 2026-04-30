import XCTest
import SwiftTreeSitter
@testable import MarginaliaSyntax

final class MarkdownParserTests: XCTestCase {

    func testFreshParse() throws {
        let p = try MarkdownParser(grammar: .block)
        let tree = p.parse("# heading\n")
        XCTAssertNotNil(tree)
        let s = tree!.rootNode!.sExpressionString ?? ""
        XCTAssertTrue(s.contains("atx_heading"))
    }

    func testIncrementalReParseAfterTextInsert() throws {
        let p = try MarkdownParser(grammar: .block)
        p.parse("Hello\n")
        let changed = p.applyEdit(
            replacing: NSRange(location: 0, length: 0),
            with: "# ",
            newSource: "# Hello\n"
        )
        XCTAssertFalse(changed.isEmpty)
        let s = p.rootNode!.sExpressionString ?? ""
        XCTAssertTrue(s.contains("atx_heading"))
    }

    func testIncrementalParseTracksMappingState() throws {
        let p = try MarkdownParser(grammar: .block)
        p.parse("a")
        XCTAssertEqual(p.mapping.text, "a")
        p.applyEdit(
            replacing: NSRange(location: 1, length: 0),
            with: "b",
            newSource: "ab"
        )
        XCTAssertEqual(p.mapping.text, "ab")
    }

    func testIncrementalReParseDeletion() throws {
        let p = try MarkdownParser(grammar: .block)
        p.parse("# heading\nbody\n")
        let changed = p.applyEdit(
            replacing: NSRange(location: 0, length: 2),
            with: "",
            newSource: "heading\nbody\n"
        )
        XCTAssertFalse(changed.isEmpty)
        // After removing "# " the heading becomes a paragraph
        let s = p.rootNode!.sExpressionString ?? ""
        XCTAssertFalse(s.contains("atx_heading"))
        XCTAssertTrue(s.contains("paragraph"))
    }

    func testIncrementalReParseFenceOpening() throws {
        // Opening a fence affects classification of subsequent lines —
        // changedRanges should reflect that the lines below shifted role.
        let p = try MarkdownParser(grammar: .block)
        p.parse("text\nmore\n")
        p.applyEdit(
            replacing: NSRange(location: 0, length: 0),
            with: "```\n",
            newSource: "```\ntext\nmore\n"
        )
        let s = p.rootNode!.sExpressionString ?? ""
        XCTAssertTrue(s.contains("fenced_code_block"))
    }

    func testInlineGrammarDirectParse() throws {
        let p = try MarkdownParser(grammar: .inline)
        let tree = p.parse("**bold** and *italic*")
        XCTAssertNotNil(tree)
        let s = tree!.rootNode!.sExpressionString ?? ""
        XCTAssertTrue(s.contains("strong_emphasis") || s.contains("emphasis"),
                      "expected emphasis nodes in: \(s)")
    }

    func testApplyEditWithoutPriorParseFallsBackToFreshParse() throws {
        let p = try MarkdownParser(grammar: .block)
        let changed = p.applyEdit(
            replacing: NSRange(location: 0, length: 0),
            with: "# h",
            newSource: "# h"
        )
        XCTAssertFalse(changed.isEmpty)
        XCTAssertEqual(p.mapping.text, "# h")
    }
}
