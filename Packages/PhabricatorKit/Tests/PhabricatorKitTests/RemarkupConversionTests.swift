import XCTest
@testable import PhabricatorKit

final class RemarkupConversionTests: XCTestCase {
    func testItalicConversion() {
        XCTAssertEqual(
            Remarkup.toCommonMark("This is //italic// text"),
            "This is *italic* text"
        )
    }

    func testItalicDoesNotEatURLs() {
        let result = Remarkup.toCommonMark("see http://example.com/path")
        XCTAssertEqual(result, "see http://example.com/path")
    }

    func testItalicDoesNotEatHTTPSScheme() {
        let result = Remarkup.toCommonMark("see https://example.com here")
        XCTAssertEqual(result, "see https://example.com here")
    }

    func testMonospaceConversion() {
        XCTAssertEqual(
            Remarkup.toCommonMark("call ##doStuff()## now"),
            "call `doStuff()` now"
        )
    }

    func testMonospaceDoesNotMatchHeader() {
        XCTAssertEqual(
            Remarkup.toCommonMark("## A header line"),
            "## A header line"
        )
    }

    func testUnderlineConversion() {
        XCTAssertEqual(
            Remarkup.toCommonMark("__important__ note"),
            "<u>important</u> note"
        )
    }

    func testHighlightConversion() {
        XCTAssertEqual(
            Remarkup.toCommonMark("!!warning!!"),
            "**warning**"
        )
    }

    func testStrikePassesThrough() {
        XCTAssertEqual(
            Remarkup.toCommonMark("~~done~~"),
            "~~done~~"
        )
    }

    func testBoldPassesThrough() {
        XCTAssertEqual(
            Remarkup.toCommonMark("**bold**"),
            "**bold**"
        )
    }

    func testHeaderConversion() {
        XCTAssertEqual(
            Remarkup.toCommonMark("= Top ="),
            "# Top"
        )
        XCTAssertEqual(
            Remarkup.toCommonMark("== Sub =="),
            "## Sub"
        )
        XCTAssertEqual(
            Remarkup.toCommonMark("=== Deep"),
            "### Deep"
        )
    }

    func testNoteCallout() {
        XCTAssertEqual(
            Remarkup.toCommonMark("NOTE: be careful"),
            "> **Note:** be careful"
        )
    }

    func testWarningCallout() {
        XCTAssertEqual(
            Remarkup.toCommonMark("WARNING: don't"),
            "> **Warning:** don't"
        )
    }

    func testImportantCallout() {
        XCTAssertEqual(
            Remarkup.toCommonMark("IMPORTANT: do"),
            "> **Important:** do"
        )
    }

    func testCalloutNotMatchedMidLine() {
        XCTAssertEqual(
            Remarkup.toCommonMark("see NOTE: in the docs"),
            "see NOTE: in the docs"
        )
    }

    func testFenceLanguageRewrite() {
        let input = """
        ```lang=swift
        let x = 1
        ```
        """
        let expected = """
        ```swift
        let x = 1
        ```
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), expected)
    }

    func testBareFenceUnchanged() {
        let input = """
        ```
        plain code
        ```
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), input)
    }

    func testBareLanguageFencePreserved() {
        let input = """
        ```swift
        let x = 1
        ```
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), input)
    }

    func testFenceContentNotTransformed() {
        let input = """
        ```
        T123 //italic// stays as-is
        ```
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), input)
    }

    func testTaskAutolink() {
        XCTAssertEqual(
            Remarkup.toCommonMark("see T123 for details"),
            "see [T123](https://phabricator.services.mozilla.com/T123) for details"
        )
    }

    func testRevisionAutolink() {
        XCTAssertEqual(
            Remarkup.toCommonMark("blocked on D45678"),
            "blocked on [D45678](https://phabricator.services.mozilla.com/D45678)"
        )
    }

    func testTaskAutolinkAtLineStart() {
        XCTAssertEqual(
            Remarkup.toCommonMark("T1 is short"),
            "[T1](https://phabricator.services.mozilla.com/T1) is short"
        )
    }

    func testTaskAutolinkRespectsWordBoundary() {
        XCTAssertEqual(
            Remarkup.toCommonMark("METADATA45 should not match"),
            "METADATA45 should not match"
        )
        XCTAssertEqual(
            Remarkup.toCommonMark("D45abc should not match"),
            "D45abc should not match"
        )
    }

    func testTaskCommentAnchor() {
        XCTAssertEqual(
            Remarkup.toCommonMark("see T123#412 for details"),
            "see [T123#412](https://phabricator.services.mozilla.com/T123#412) for details"
        )
    }

    func testRevisionCommentAnchor() {
        XCTAssertEqual(
            Remarkup.toCommonMark("D45#67 has the discussion"),
            "[D45#67](https://phabricator.services.mozilla.com/D45#67) has the discussion"
        )
    }

    func testTaskAnchorRequiresDigits() {
        XCTAssertEqual(
            Remarkup.toCommonMark("T123#abc not a comment ref"),
            "[T123](https://phabricator.services.mozilla.com/T123)#abc not a comment ref"
        )
    }

    func testRepositorySVNCommit() {
        XCTAssertEqual(
            Remarkup.toCommonMark("landed in rNSPR12345"),
            "landed in [rNSPR12345](https://phabricator.services.mozilla.com/rNSPR12345)"
        )
    }

    func testRepositoryGitCommit() {
        XCTAssertEqual(
            Remarkup.toCommonMark("see rMOZILLACENTRALaf3192cd5b"),
            "see [rMOZILLACENTRALaf3192cd5b](https://phabricator.services.mozilla.com/rMOZILLACENTRALaf3192cd5b)"
        )
    }

    func testRepositoryShortHashRejected() {
        XCTAssertEqual(
            Remarkup.toCommonMark("rXabc is too short"),
            "rXabc is too short"
        )
    }

    func testRepositoryWordBoundary() {
        XCTAssertEqual(
            Remarkup.toCommonMark("released today"),
            "released today"
        )
    }

    func testEmbedFormReferences() {
        XCTAssertEqual(
            Remarkup.toCommonMark("attached {F1234} for proof"),
            "attached [F1234](https://phabricator.services.mozilla.com/F1234) for proof"
        )
    }

    func testUserMention() {
        XCTAssertEqual(
            Remarkup.toCommonMark("cc @alice please"),
            "cc [@alice](https://phabricator.services.mozilla.com/p/alice/) please"
        )
    }

    func testUserMentionAtLineStart() {
        XCTAssertEqual(
            Remarkup.toCommonMark("@bob hi"),
            "[@bob](https://phabricator.services.mozilla.com/p/bob/) hi"
        )
    }

    func testUserMentionTrailingPunctuation() {
        XCTAssertEqual(
            Remarkup.toCommonMark("ping @carol."),
            "ping [@carol](https://phabricator.services.mozilla.com/p/carol/)."
        )
    }

    func testBugReference() {
        XCTAssertEqual(
            Remarkup.toCommonMark("fixes bug 1234567 today"),
            "fixes [bug 1234567](https://bugzilla.mozilla.org/show_bug.cgi?id=1234567) today"
        )
    }

    func testCapitalBugReference() {
        XCTAssertEqual(
            Remarkup.toCommonMark("Bug 999 is open"),
            "[Bug 999](https://bugzilla.mozilla.org/show_bug.cgi?id=999) is open"
        )
    }

    func testInlineCodeProtectsContent() {
        XCTAssertEqual(
            Remarkup.toCommonMark("type `T123` literally"),
            "type `T123` literally"
        )
    }

    func testInlineCodeDoesNotEatItalic() {
        XCTAssertEqual(
            Remarkup.toCommonMark("`code` and //italic//"),
            "`code` and *italic*"
        )
    }

    func testExistingMarkdownLinkPreserved() {
        XCTAssertEqual(
            Remarkup.toCommonMark("[click](https://example.com/path) here"),
            "[click](https://example.com/path) here"
        )
    }

    func testExistingLinkAroundReferenceNotDoubleLinked() {
        let input = "[T999 details](https://phabricator.services.mozilla.com/T999)"
        XCTAssertEqual(Remarkup.toCommonMark(input), input)
    }

    func testOrderedListRunConverts() {
        let input = """
        # Articuno
        # Zapdos
        # Moltres
        """
        let expected = """
        1. Articuno
        2. Zapdos
        3. Moltres
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), expected)
    }

    func testSingleHashLineStaysHeader() {
        XCTAssertEqual(
            Remarkup.toCommonMark("# Just a header"),
            "# Just a header"
        )
    }

    func testOrderedListResetsAfterBreak() {
        let input = """
        # one
        # two

        prose

        # three
        # four
        """
        let expected = """
        1. one
        2. two

        prose

        1. three
        2. four
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), expected)
    }

    func testNestedOrderedListNumberedPerIndent() {
        let input = """
        - Hand
          # Thumb
          # Index
        - Foot
        """
        let expected = """
        - Hand
          1. Thumb
          2. Index
        - Foot
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), expected)
    }

    func testHashLinesInsideFenceUnchanged() {
        let input = """
        ```
        # not a list
        # still not a list
        ```
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), input)
    }

    func testBracketLinkNamedExternal() {
        XCTAssertEqual(
            Remarkup.toCommonMark("[[http://example.com/path | example]]"),
            "[example](http://example.com/path)"
        )
    }

    func testBracketLinkBareExternal() {
        XCTAssertEqual(
            Remarkup.toCommonMark("[[https://example.com]]"),
            "[https://example.com](https://example.com)"
        )
    }

    func testBracketLinkPhabricatorPath() {
        XCTAssertEqual(
            Remarkup.toCommonMark("[[/herald/transcript/ | Herald Transcripts]]"),
            "[Herald Transcripts](https://phabricator.services.mozilla.com/herald/transcript/)"
        )
    }

    func testBracketLinkPhrictionNamed() {
        XCTAssertEqual(
            Remarkup.toCommonMark("[[legal/boring_documents/ | exciting legal documents]]"),
            "[exciting legal documents](https://phabricator.services.mozilla.com/w/legal/boring_documents/)"
        )
    }

    func testBracketLinkPhrictionBare() {
        XCTAssertEqual(
            Remarkup.toCommonMark("[[wiki page]]"),
            "[wiki page](https://phabricator.services.mozilla.com/w/wiki%20page)"
        )
    }

    func testBracketLinkInsideSentence() {
        XCTAssertEqual(
            Remarkup.toCommonMark("see [[/D123 | the revision]] for context"),
            "see [the revision](https://phabricator.services.mozilla.com/D123) for context"
        )
    }

    func testBracketLinkInsideInlineCodeUntouched() {
        XCTAssertEqual(
            Remarkup.toCommonMark("syntax is `[[target | name]]` here"),
            "syntax is `[[target | name]]` here"
        )
    }

    func testCustomBaseURLs() {
        let phab = URL(string: "https://phab.example.com")!
        let bz = URL(string: "https://bz.example.com")!
        XCTAssertEqual(
            Remarkup.toCommonMark("T1 and bug 2", phabricatorBaseURL: phab, bugzillaBaseURL: bz),
            "[T1](https://phab.example.com/T1) and [bug 2](https://bz.example.com/show_bug.cgi?id=2)"
        )
    }

    func testCombinedRemarkupBlock() {
        let input = """
        = Summary =

        NOTE: this fixes bug 1234567.

        See //the docs// or T42 for context. Use ##makeFoo()##.

        ```lang=swift
        let x = 1
        ```
        """
        let expected = """
        # Summary

        > **Note:** this fixes [bug 1234567](https://bugzilla.mozilla.org/show_bug.cgi?id=1234567).

        See *the docs* or [T42](https://phabricator.services.mozilla.com/T42) for context. Use `makeFoo()`.

        ```swift
        let x = 1
        ```
        """
        XCTAssertEqual(Remarkup.toCommonMark(input), expected)
    }
}
