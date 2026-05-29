import Foundation
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
}
