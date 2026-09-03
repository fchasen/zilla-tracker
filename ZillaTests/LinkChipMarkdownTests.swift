import Foundation
import PhabricatorKit
import Testing
@testable import Zilla

struct LinkChipMarkdownTests {
    @Test func searchfoxTargetUsesFileNameAndLine() throws {
        let url = try #require(URL(string: "https://searchfox.org/mozilla-central/source/dom/base/Document.cpp#123"))
        let target = try #require(ZillaLinkChipTarget.target(for: url))

        #expect(target.label == "Document.cpp:123")
        #expect(target.kind == .searchfox)
    }

    @Test func searchfoxTargetSupportsLineRanges() throws {
        let url = try #require(URL(string: "https://searchfox.org/mozilla-central/rev/abc123/browser/base/content/browser.js#L40-L45"))
        let target = try #require(ZillaLinkChipTarget.target(for: url))

        #expect(target.label == "browser.js:40-45")
    }

    @Test func bugzillaTargetUsesBugID() throws {
        let url = try #require(URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=1900000#c3"))
        let target = try #require(ZillaLinkChipTarget.target(for: url))

        #expect(target.label == "Bug 1900000")
        #expect(target.kind == .bug)
    }

    @Test func bugzillaTargetUsesAttachmentID() throws {
        let url = try #require(URL(string: "https://bugzilla.mozilla.org/attachment.cgi?id=123456"))
        let target = try #require(ZillaLinkChipTarget.target(for: url))

        #expect(target.label == "Attachment 123456")
        #expect(target.kind == .attachment)
    }

    @Test @MainActor func parserShortensBareSupportedURLs() throws {
        let parser = ZillaLinkMarkdownParser()
        let rendered = try parser.attributedString(
            for: "See https://searchfox.org/mozilla-central/source/js/src/vm/StringType.h#77."
        )

        #expect(String(rendered.characters) == "See \u{FFFC}.")
    }

    @Test @MainActor func parserLeavesCodeURLsReadable() throws {
        let parser = ZillaLinkMarkdownParser()
        let rendered = try parser.attributedString(
            for: "`https://bugzilla.mozilla.org/show_bug.cgi?id=1900000`"
        )

        #expect(String(rendered.characters) == "https://bugzilla.mozilla.org/show_bug.cgi?id=1900000")
    }

    // MARK: - conventional comment labels

    @Test @MainActor func commentLabelRendersAsABareIcon() throws {
        let parser = ZillaLinkMarkdownParser()
        let rendered = try parser.attributedString(for: "{nav,  icon=sticky-note, name=note:} looks good")

        #expect(String(rendered.characters) == "\u{FFFC} looks good")
        // Icon only — nothing to click, so nothing carries a link.
        #expect(rendered.runs.allSatisfy { $0.link == nil })
    }

    @Test @MainActor func commentLabelSurvivesTheRemarkupConversion() throws {
        let parser = ZillaLinkMarkdownParser()
        let markdown = Remarkup.toCommonMark("{nav,  icon=sticky-note, name=note:} looks good")
        let rendered = try parser.attributedString(for: markdown)

        #expect(String(rendered.characters) == "\u{FFFC} looks good")
    }

    @Test @MainActor func commentLabelInsideACodeSpanStaysLiteral() throws {
        let parser = ZillaLinkMarkdownParser()
        let rendered = try parser.attributedString(for: "use `{nav, icon=x, name=y:}` here")

        #expect(String(rendered.characters) == "use {nav, icon=x, name=y:} here")
    }

    @Test @MainActor func twoCommentLabelsOnOneLineBothRender() throws {
        let parser = ZillaLinkMarkdownParser()
        let rendered = try parser.attributedString(
            for: "{nav, icon=bug, name=issue:} and {nav, icon=comment, name=note:} end"
        )

        #expect(String(rendered.characters) == "\u{FFFC} and \u{FFFC} end")
    }

    @Test @MainActor func aCommentLabelAndABareBugURLBothRender() throws {
        let parser = ZillaLinkMarkdownParser()
        let rendered = try parser.attributedString(
            for: "{nav, icon=bug, name=issue:} see https://bugzilla.mozilla.org/show_bug.cgi?id=1900000"
        )

        #expect(String(rendered.characters) == "\u{FFFC} see \u{FFFC}")
    }

    @Test @MainActor func aMalformedTokenStaysLiteral() throws {
        let parser = ZillaLinkMarkdownParser()
        let rendered = try parser.attributedString(for: "{navigate} and {nav, name=note:}")

        #expect(String(rendered.characters) == "{navigate} and {nav, name=note:}")
    }

    @Test func everyCommentLabelIconMapsToARealSymbol() {
        for label in CommentLabels.all {
            #expect(
                label.systemImage != PhabricatorIcons.fallbackSystemImage,
                "\(label.name) fell back for icon \(label.icon)"
            )
        }
    }

    @Test func anUnmappedIconFallsBackRatherThanFailing() {
        #expect(PhabricatorIcons.systemImage(for: "lemon-o") == PhabricatorIcons.fallbackSystemImage)
    }

    @Test func theTokenParserReadsIconAndName() throws {
        let parsed = try #require(CommentLabels.parse("{nav,  icon=sticky-note, name=note:}"))

        #expect(parsed.icon == "sticky-note")
        #expect(parsed.name == "note:")
    }

    @Test func theTokenParserRejectsAMalformedToken() {
        #expect(CommentLabels.parse("{navigate}") == nil)
        #expect(CommentLabels.parse("{nav, name=note:}") == nil)
    }

    /// The extension prefixes `issue:` with `(IMPORTANT)`; Zilla must not,
    /// because that callout has no way back through `Markdown.toRemarkup`.
    @Test func insertionTextCarriesNoImportantPrefix() throws {
        let issue = try #require(CommentLabels.label(named: "issue:"))

        #expect(CommentLabels.insertionText(for: issue) == "{nav, icon=exclamation-triangle, name=issue:} ")
    }
}
