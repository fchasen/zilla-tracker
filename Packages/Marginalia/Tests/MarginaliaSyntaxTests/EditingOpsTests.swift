import XCTest
@testable import MarginaliaSyntax

final class EditingOpsTests: XCTestCase {

    // MARK: - wrap

    func testWrapEmptyTextEmptySelection() {
        let result = EditingOps.wrap(
            in: "",
            selection: NSRange(location: 0, length: 0),
            prefix: "**", suffix: "**", placeholder: "bold"
        )
        XCTAssertEqual(result.text, "**bold**")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 4))
    }

    func testWrapInsertsAtCursorNotAtEnd() {
        let result = EditingOps.wrap(
            in: "hello world",
            selection: NSRange(location: 6, length: 0),
            prefix: "*", suffix: "*", placeholder: "italic"
        )
        XCTAssertEqual(result.text, "hello *italic*world")
        XCTAssertEqual(result.selection, NSRange(location: 7, length: 6))
    }

    func testWrapNonEmptySelection() {
        let result = EditingOps.wrap(
            in: "hello world",
            selection: NSRange(location: 0, length: 5),
            prefix: "**", suffix: "**", placeholder: "bold"
        )
        XCTAssertEqual(result.text, "**hello** world")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 9))
    }

    func testWrapSelectionAtEnd() {
        let result = EditingOps.wrap(
            in: "hello world",
            selection: NSRange(location: 6, length: 5),
            prefix: "**", suffix: "**", placeholder: "bold"
        )
        XCTAssertEqual(result.text, "hello **world**")
        XCTAssertEqual(result.selection, NSRange(location: 6, length: 9))
    }

    func testWrapAsymmetricMarkers() {
        let result = EditingOps.wrap(
            in: "click here",
            selection: NSRange(location: 0, length: 5),
            prefix: "[", suffix: "](url)", placeholder: "label"
        )
        XCTAssertEqual(result.text, "[click](url) here")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 12))
    }

    func testWrapPreservesUnicodeUTF16Lengths() {
        // 🚀 is one Character, two UTF-16 code units
        let result = EditingOps.wrap(
            in: "🚀x",
            selection: NSRange(location: 2, length: 1),
            prefix: "*", suffix: "*", placeholder: "italic"
        )
        XCTAssertEqual(result.text, "🚀*x*")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 3))
    }

    // MARK: - prefixLines

    func testPrefixLinesEmptyText() {
        let result = EditingOps.prefixLines(
            in: "",
            selection: NSRange(location: 0, length: 0),
            marker: "- "
        )
        XCTAssertEqual(result.text, "- ")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 0))
    }

    func testPrefixLinesCursorAtEndOfLine() {
        let result = EditingOps.prefixLines(
            in: "hello",
            selection: NSRange(location: 5, length: 0),
            marker: "- "
        )
        XCTAssertEqual(result.text, "- hello")
        XCTAssertEqual(result.selection, NSRange(location: 7, length: 0))
    }

    func testPrefixLinesCursorMidLine() {
        let result = EditingOps.prefixLines(
            in: "hello world",
            selection: NSRange(location: 6, length: 0),
            marker: "- "
        )
        XCTAssertEqual(result.text, "- hello world")
        XCTAssertEqual(result.selection, NSRange(location: 8, length: 0))
    }

    func testPrefixLinesSingleLineSelection() {
        let result = EditingOps.prefixLines(
            in: "hello",
            selection: NSRange(location: 0, length: 5),
            marker: "- "
        )
        XCTAssertEqual(result.text, "- hello")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 7))
    }

    func testPrefixLinesMultiLineSelection() {
        let result = EditingOps.prefixLines(
            in: "hello\nworld\nfoo",
            selection: NSRange(location: 0, length: 11),
            marker: "- "
        )
        XCTAssertEqual(result.text, "- hello\n- world\nfoo")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 15))
    }

    func testPrefixLinesPartialSelectionExtendsToFullLines() {
        let result = EditingOps.prefixLines(
            in: "hello\nworld\nfoo",
            selection: NSRange(location: 2, length: 5),
            marker: "- "
        )
        XCTAssertEqual(result.text, "- hello\n- world\nfoo")
    }

    func testPrefixLinesSelectionIncludingTrailingNewline() {
        let result = EditingOps.prefixLines(
            in: "hello\nworld",
            selection: NSRange(location: 0, length: 6),
            marker: "- "
        )
        XCTAssertEqual(result.text, "- hello\nworld")
    }

    func testPrefixLinesBlockquoteMarker() {
        let result = EditingOps.prefixLines(
            in: "a\nb",
            selection: NSRange(location: 0, length: 3),
            marker: "> "
        )
        XCTAssertEqual(result.text, "> a\n> b")
    }

    // MARK: - numberedList

    func testNumberedListEmptyText() {
        let result = EditingOps.numberedList(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(result.text, "1. ")
        XCTAssertEqual(result.selection, NSRange(location: 3, length: 0))
    }

    func testNumberedListCursorOnLine() {
        let result = EditingOps.numberedList(
            in: "hello",
            selection: NSRange(location: 5, length: 0)
        )
        XCTAssertEqual(result.text, "1. hello")
    }

    func testNumberedListMultiLineSelection() {
        let result = EditingOps.numberedList(
            in: "first\nsecond\nthird",
            selection: NSRange(location: 0, length: 18)
        )
        XCTAssertEqual(result.text, "1. first\n2. second\n3. third")
    }

    func testNumberedListNumbersExceedingTen() {
        let lines = (1...12).map { "line\($0)" }.joined(separator: "\n")
        let result = EditingOps.numberedList(
            in: lines,
            selection: NSRange(location: 0, length: (lines as NSString).length)
        )
        XCTAssertTrue(result.text.contains("10. line10"))
        XCTAssertTrue(result.text.contains("11. line11"))
        XCTAssertTrue(result.text.contains("12. line12"))
    }

    // MARK: - wrapCodeBlock

    func testWrapCodeBlockEmptyText() {
        let result = EditingOps.wrapCodeBlock(
            in: "",
            selection: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(result.text, "```\ncode\n```\n")
        XCTAssertEqual(result.selection, NSRange(location: 4, length: 4))
    }

    func testWrapCodeBlockAtStartOfNewLine() {
        let result = EditingOps.wrapCodeBlock(
            in: "hello\n",
            selection: NSRange(location: 6, length: 0)
        )
        XCTAssertEqual(result.text, "hello\n```\ncode\n```\n")
        XCTAssertEqual(result.selection, NSRange(location: 10, length: 4))
    }

    func testWrapCodeBlockMidLineAddsLeadingNewline() {
        let result = EditingOps.wrapCodeBlock(
            in: "hello world",
            selection: NSRange(location: 6, length: 0)
        )
        XCTAssertEqual(result.text, "hello \n```\ncode\n```\nworld")
    }

    func testWrapCodeBlockSelectionAtLineStart() {
        let result = EditingOps.wrapCodeBlock(
            in: "let x = 1",
            selection: NSRange(location: 0, length: 9)
        )
        XCTAssertEqual(result.text, "```\nlet x = 1\n```\n")
    }

    func testWrapCodeBlockSelectionWithTrailingNewline() {
        let result = EditingOps.wrapCodeBlock(
            in: "let x = 1\n",
            selection: NSRange(location: 0, length: 10)
        )
        XCTAssertEqual(result.text, "```\nlet x = 1\n```\n")
    }

    func testWrapCodeBlockSelectionMidLine() {
        let result = EditingOps.wrapCodeBlock(
            in: "before code after",
            selection: NSRange(location: 7, length: 4)
        )
        XCTAssertEqual(result.text, "before \n```\ncode\n```\n after")
    }

    func testWrapCodeBlockCustomPlaceholder() {
        let result = EditingOps.wrapCodeBlock(
            in: "",
            selection: NSRange(location: 0, length: 0),
            placeholder: "swift"
        )
        XCTAssertEqual(result.text, "```\nswift\n```\n")
        XCTAssertEqual(result.selection, NSRange(location: 4, length: 5))
    }

    // MARK: - EditResult

    func testEditResultEquality() {
        let a = EditResult(text: "hello", selection: NSRange(location: 1, length: 2))
        let b = EditResult(text: "hello", selection: NSRange(location: 1, length: 2))
        let c = EditResult(text: "world", selection: NSRange(location: 1, length: 2))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
