import XCTest
@testable import PhabricatorKit

final class MarkdownConversionTests: XCTestCase {
    func testItalicAsterisk() {
        XCTAssertEqual(
            Markdown.toRemarkup("This is *italic* text"),
            "This is //italic// text"
        )
    }

    func testItalicUnderscore() {
        XCTAssertEqual(
            Markdown.toRemarkup("This is _italic_ text"),
            "This is //italic// text"
        )
    }

    func testItalicAtLineStart() {
        XCTAssertEqual(
            Markdown.toRemarkup("*italic* at start"),
            "//italic// at start"
        )
    }

    func testBoldStaysAsterisks() {
        XCTAssertEqual(
            Markdown.toRemarkup("**bold** text"),
            "**bold** text"
        )
    }

    func testUnderscoreBoldBecomesAsterisks() {
        XCTAssertEqual(
            Markdown.toRemarkup("__bold__ text"),
            "**bold** text"
        )
    }

    func testBoldWithItalicInside() {
        XCTAssertEqual(
            Markdown.toRemarkup("**bold _italic_ bold**"),
            "**bold //italic// bold**"
        )
    }

    func testBulletListAsteriskNotItalic() {
        XCTAssertEqual(
            Markdown.toRemarkup("* item one"),
            "* item one"
        )
    }

    func testSnakeCaseNotItalic() {
        XCTAssertEqual(
            Markdown.toRemarkup("call my_var_name here"),
            "call my_var_name here"
        )
    }

    func testInlineCodeBackticks() {
        XCTAssertEqual(
            Markdown.toRemarkup("call `doStuff()` now"),
            "call ##doStuff()## now"
        )
    }

    func testInlineCodeProtectsContent() {
        XCTAssertEqual(
            Markdown.toRemarkup("see `*not italic*` here"),
            "see ##*not italic*## here"
        )
    }

    func testATXHeaderH1() {
        XCTAssertEqual(
            Markdown.toRemarkup("# Top"),
            "= Top ="
        )
    }

    func testATXHeaderH2() {
        XCTAssertEqual(
            Markdown.toRemarkup("## Sub"),
            "== Sub =="
        )
    }

    func testATXHeaderWithTrailingHashes() {
        XCTAssertEqual(
            Markdown.toRemarkup("### Foo ###"),
            "=== Foo ==="
        )
    }

    func testHashtagWithoutSpaceLeftAlone() {
        XCTAssertEqual(
            Markdown.toRemarkup("see #tag here"),
            "see #tag here"
        )
    }

    func testSetextH1() {
        let input = """
        Title
        =====
        body
        """
        let expected = """
        = Title =
        body
        """
        XCTAssertEqual(Markdown.toRemarkup(input), expected)
    }

    func testSetextH2() {
        let input = """
        Subtitle
        --------
        body
        """
        let expected = """
        == Subtitle ==
        body
        """
        XCTAssertEqual(Markdown.toRemarkup(input), expected)
    }

    func testSetextNotTriggeredByDashHRAfterBlank() {
        let input = """
        body

        ---
        """
        XCTAssertEqual(Markdown.toRemarkup(input), input)
    }

    func testMarkdownLinkWithLabel() {
        XCTAssertEqual(
            Markdown.toRemarkup("see [the docs](https://example.com/docs)"),
            "see [[https://example.com/docs | the docs]]"
        )
    }

    func testAutolinkAngleBrackets() {
        XCTAssertEqual(
            Markdown.toRemarkup("see <https://example.com>"),
            "see https://example.com"
        )
    }

    func testBareURLLeftAlone() {
        XCTAssertEqual(
            Markdown.toRemarkup("see https://example.com here"),
            "see https://example.com here"
        )
    }

    func testItalicDoesNotEatURL() {
        XCTAssertEqual(
            Markdown.toRemarkup("*see https://example.com here*"),
            "//see https://example.com here//"
        )
    }

    func testImageBecomesLink() {
        XCTAssertEqual(
            Markdown.toRemarkup("![alt text](https://example.com/img.png)"),
            "[[https://example.com/img.png | alt text]]"
        )
    }

    func testFencedCodeUnchanged() {
        let input = """
        ```swift
        let x = *not italic*
        # not a header
        ```
        """
        XCTAssertEqual(Markdown.toRemarkup(input), input)
    }

    func testATXInsideFenceUntouched() {
        let input = """
        ```python
        # comment
        print("hi")
        ```
        """
        XCTAssertEqual(Markdown.toRemarkup(input), input)
    }

    func testExistingRemarkupBracketLinkPassesThrough() {
        XCTAssertEqual(
            Markdown.toRemarkup("see [[T123 | task]] now"),
            "see [[T123 | task]] now"
        )
    }

    func testStrikePassesThrough() {
        XCTAssertEqual(
            Markdown.toRemarkup("~~done~~"),
            "~~done~~"
        )
    }

    func testBlockquotePassesThrough() {
        XCTAssertEqual(
            Markdown.toRemarkup("> a quote"),
            "> a quote"
        )
    }

    func testNumberedListPassesThrough() {
        let input = """
        1. one
        2. two
        """
        XCTAssertEqual(Markdown.toRemarkup(input), input)
    }

    func testHorizontalRulePassesThrough() {
        let input = """
        before

        ---

        after
        """
        XCTAssertEqual(Markdown.toRemarkup(input), input)
    }

    func testMixedItalicBoldCode() {
        XCTAssertEqual(
            Markdown.toRemarkup("Use **bold** and *italic* and `code`."),
            "Use **bold** and //italic// and ##code##."
        )
    }

    func testHeaderItalicCombo() {
        XCTAssertEqual(
            Markdown.toRemarkup("## *italic* heading"),
            "== //italic// heading =="
        )
    }

    func testRoundTripItalic() {
        let remarkup = "This is //italic// text"
        let asMarkdown = Remarkup.toCommonMark(remarkup)
        XCTAssertEqual(Markdown.toRemarkup(asMarkdown), remarkup)
    }

    func testRoundTripHeader() {
        let remarkup = "= Title ="
        let asMarkdown = Remarkup.toCommonMark(remarkup)
        XCTAssertEqual(Markdown.toRemarkup(asMarkdown), remarkup)
    }

    func testRoundTripFencedCode() {
        let remarkup = """
        ```swift
        let x = 1
        ```
        """
        let asMarkdown = Remarkup.toCommonMark(remarkup)
        XCTAssertEqual(Markdown.toRemarkup(asMarkdown), remarkup)
    }

    func testCRLFNormalized() {
        XCTAssertEqual(
            Markdown.toRemarkup("line one\r\nline two"),
            "line one\nline two"
        )
    }
}
