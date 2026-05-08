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
}
