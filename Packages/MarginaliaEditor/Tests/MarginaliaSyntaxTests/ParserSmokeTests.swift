import XCTest
import SwiftTreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownInline
@testable import MarginaliaSyntax

final class ParserSmokeTests: XCTestCase {

    func testBlockGrammarLoads() throws {
        let parser = Parser()
        XCTAssertNoThrow(try parser.setLanguage(Language(language: tree_sitter_markdown())))
    }

    func testInlineGrammarLoads() throws {
        let parser = Parser()
        XCTAssertNoThrow(try parser.setLanguage(Language(language: tree_sitter_markdown_inline())))
    }

    func testParsesAtxHeading() throws {
        let parser = Parser()
        try parser.setLanguage(Language(language: tree_sitter_markdown()))
        let source = "# heading\n"
        let tree = parser.parse(source)
        XCTAssertNotNil(tree)
        let root = tree!.rootNode
        XCTAssertNotNil(root)
        let s = root!.sExpressionString ?? ""
        XCTAssertTrue(s.contains("atx_heading"), "expected atx_heading in: \(s)")
    }

    func testParsesFencedCodeBlock() throws {
        let parser = Parser()
        try parser.setLanguage(Language(language: tree_sitter_markdown()))
        let source = "```\nlet x = 1\n```\n"
        let tree = parser.parse(source)!
        let s = tree.rootNode!.sExpressionString ?? ""
        XCTAssertTrue(s.contains("fenced_code_block"), "expected fenced_code_block in: \(s)")
    }

    func testIncrementalParseChangedRanges() throws {
        let parser = Parser()
        try parser.setLanguage(Language(language: tree_sitter_markdown()))
        let source1 = "Hello\n"
        let tree1 = parser.parse(source1)!

        // Insert "# " at offset 0 (turns "Hello" into a heading)
        let edit = InputEdit(
            startByte: 0,
            oldEndByte: 0,
            newEndByte: 2,
            startPoint: Point(row: 0, column: 0),
            oldEndPoint: Point(row: 0, column: 0),
            newEndPoint: Point(row: 0, column: 2)
        )
        tree1.edit(edit)
        let source2 = "# Hello\n"
        let tree2 = parser.parse(tree: tree1, string: source2)!

        let changed = tree1.changedRanges(from: tree2)
        XCTAssertFalse(changed.isEmpty, "expected at least one changed range")
    }
}
