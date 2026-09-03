import PhabricatorKit
import Testing
@testable import Zilla

struct CommentMarkdownTests {
    @Test func autolinksRevisionBugWordAndBugHashReferences() {
        let markdown = "See D12345, bug 23456 and #34567."

        #expect(CommentMarkdown.autolinkReferences(in: markdown) == "See [D12345](https://phabricator.services.mozilla.com/D12345), [bug 23456](https://bugzilla.mozilla.org/show_bug.cgi?id=23456) and [#34567](https://bugzilla.mozilla.org/show_bug.cgi?id=34567).")
    }

    @Test func preservesExistingLinksAndCode() {
        let markdown = """
        Keep [D123](https://example.com) and `bug 234`.
        ```
        D345 and #456 stay literal
        ```
        """

        #expect(CommentMarkdown.autolinkReferences(in: markdown) == markdown)
    }

    /// What a reviewer's existing comment does on the way in and back out:
    /// the double space the extension emits has to survive untouched, or the
    /// repost rewrites their text.
    @Test func aCommentLabelRoundTripsThroughTheComposer() {
        let remarkup = "{nav,  icon=sticky-note, name=note:} looks good"
        let editorMarkdown = CommentMarkdown.autolinkReferences(in: Remarkup.toCommonMark(remarkup))

        #expect(editorMarkdown == remarkup)
        #expect(Markdown.toRemarkup(editorMarkdown) == remarkup)
    }

    @Test func autolinkingLeavesACommentLabelAlone() {
        let markdown = "{nav, icon=bug, name=bug 123 and D45} see bug 23456"

        #expect(CommentMarkdown.autolinkReferences(in: markdown) == "{nav, icon=bug, name=bug 123 and D45} see [bug 23456](https://bugzilla.mozilla.org/show_bug.cgi?id=23456)")
    }

    @Test func anUneditedCommentLabelRepostsByteForByte() {
        for remarkup in [
            "{nav,  icon=sticky-note, name=note:} looks good",
            "{nav, icon=exclamation-triangle, name=issue:} this breaks",
            "{nav icon=thumbs-up, name=praise:} nice work"
        ] {
            let editorMarkdown = CommentMarkdown.autolinkReferences(in: Remarkup.toCommonMark(remarkup))
            #expect(Markdown.toRemarkup(editorMarkdown) == remarkup)
        }
    }
}
