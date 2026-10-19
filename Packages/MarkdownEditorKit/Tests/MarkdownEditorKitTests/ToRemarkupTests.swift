import Foundation
import Testing
@testable import MarkdownEditorKit
import PhabricatorKit

struct MarkCase: CustomTestStringConvertible, Sendable {
    let marks: EditorDocument.InlineMarks
    let markdown: String
    let remarkup: String
    let linkedMarkdown: String
    let linkedRemarkup: String

    var testDescription: String {
        var names: [String] = []
        if marks.contains(.strong) { names.append("strong") }
        if marks.contains(.emphasis) { names.append("emphasis") }
        if marks.contains(.code) { names.append("code") }
        if marks.contains(.strikethrough) { names.append("strikethrough") }
        return names.isEmpty ? "plain" : names.joined(separator: "+")
    }

    var hasKnownToRemarkupGap: Bool {
        marks.contains(.code) && (marks.contains(.emphasis))
    }

    var hasKnownLinkedToRemarkupGap: Bool {
        marks.contains(.code)
    }
}

enum RemarkupCases {
    static let url = "https://example.com/p"

    static let marks: [MarkCase] = [
        MarkCase(marks: [], markdown: "a word b", remarkup: "a word b",
                 linkedMarkdown: "a [word](\(url)) b", linkedRemarkup: "a [[\(url) | word]] b"),
        MarkCase(marks: [.strong], markdown: "a **word** b", remarkup: "a **word** b",
                 linkedMarkdown: "a **[word](\(url))** b", linkedRemarkup: "a **[[\(url) | word]]** b"),
        MarkCase(marks: [.emphasis], markdown: "a *word* b", remarkup: "a //word// b",
                 linkedMarkdown: "a *[word](\(url))* b", linkedRemarkup: "a //[[\(url) | word]]// b"),
        MarkCase(marks: [.strong, .emphasis], markdown: "a ***word*** b", remarkup: "a //**word**// b",
                 linkedMarkdown: "a ***[word](\(url))*** b", linkedRemarkup: "a //**[[\(url) | word]]**// b"),
        MarkCase(marks: [.code], markdown: "a `word` b", remarkup: "a ##word## b",
                 linkedMarkdown: "a [`word`](\(url)) b", linkedRemarkup: "a [[\(url) | ##word##]] b"),
        MarkCase(marks: [.strong, .code], markdown: "a **`word`** b", remarkup: "a **##word##** b",
                 linkedMarkdown: "a **[`word`](\(url))** b", linkedRemarkup: "a **[[\(url) | ##word##]]** b"),
        MarkCase(marks: [.emphasis, .code], markdown: "a *`word`* b", remarkup: "a //##word##// b",
                 linkedMarkdown: "a *[`word`](\(url))* b", linkedRemarkup: "a //[[\(url) | ##word##]]// b"),
        MarkCase(marks: [.strong, .emphasis, .code], markdown: "a ***`word`*** b", remarkup: "a //**##word##**// b",
                 linkedMarkdown: "a ***[`word`](\(url))*** b", linkedRemarkup: "a //**[[\(url) | ##word##]]**// b"),
        MarkCase(marks: [.strikethrough], markdown: "a ~~word~~ b", remarkup: "a ~~word~~ b",
                 linkedMarkdown: "a ~~[word](\(url))~~ b", linkedRemarkup: "a ~~[[\(url) | word]]~~ b"),
        MarkCase(marks: [.strikethrough, .strong], markdown: "a ~~**word**~~ b", remarkup: "a ~~**word**~~ b",
                 linkedMarkdown: "a ~~**[word](\(url))**~~ b", linkedRemarkup: "a ~~**[[\(url) | word]]**~~ b"),
        MarkCase(marks: [.strikethrough, .emphasis], markdown: "a ~~*word*~~ b", remarkup: "a ~~//word//~~ b",
                 linkedMarkdown: "a ~~*[word](\(url))*~~ b", linkedRemarkup: "a ~~//[[\(url) | word]]//~~ b"),
        MarkCase(marks: [.strikethrough, .strong, .emphasis], markdown: "a ~~***word***~~ b", remarkup: "a ~~//**word**//~~ b",
                 linkedMarkdown: "a ~~***[word](\(url))***~~ b", linkedRemarkup: "a ~~//**[[\(url) | word]]**//~~ b"),
        MarkCase(marks: [.strikethrough, .code], markdown: "a ~~`word`~~ b", remarkup: "a ~~##word##~~ b",
                 linkedMarkdown: "a ~~[`word`](\(url))~~ b", linkedRemarkup: "a ~~[[\(url) | ##word##]]~~ b"),
        MarkCase(marks: [.strikethrough, .strong, .code], markdown: "a ~~**`word`**~~ b", remarkup: "a ~~**##word##**~~ b",
                 linkedMarkdown: "a ~~**[`word`](\(url))**~~ b", linkedRemarkup: "a ~~**[[\(url) | ##word##]]**~~ b"),
        MarkCase(marks: [.strikethrough, .emphasis, .code], markdown: "a ~~*`word`*~~ b", remarkup: "a ~~//##word##//~~ b",
                 linkedMarkdown: "a ~~*[`word`](\(url))*~~ b", linkedRemarkup: "a ~~//[[\(url) | ##word##]]//~~ b"),
        MarkCase(marks: [.strikethrough, .strong, .emphasis, .code], markdown: "a ~~***`word`***~~ b", remarkup: "a ~~//**##word##**//~~ b",
                 linkedMarkdown: "a ~~***[`word`](\(url))***~~ b", linkedRemarkup: "a ~~//**[[\(url) | ##word##]]**//~~ b"),
    ]
}

@Suite("toRemarkup")
struct ToRemarkupTests {
    @Test func everyMarkCombinationIsCovered() {
        #expect(Set(RemarkupCases.marks.map(\.marks.rawValue)) == Set(0..<16))
    }

    @Test(arguments: RemarkupCases.marks)
    func writerOutputForMarks(_ mark: MarkCase) {
        #expect(WF.inline(WF.t("a "), WF.t("word", mark.marks), WF.t(" b")) == mark.markdown)
        #expect(WF.inline(WF.t("a "), WF.t("word", mark.marks, link: RemarkupCases.url), WF.t(" b")) == mark.linkedMarkdown)
    }

    @Test(arguments: RemarkupCases.marks)
    func loaderRoundTripsMarkdownForMarks(_ mark: MarkCase) {
        #expect(Corpus.roundTrip(mark.markdown) == mark.markdown)
        #expect(Corpus.roundTrip(mark.linkedMarkdown) == mark.linkedMarkdown)
    }

    @Test(arguments: RemarkupCases.marks)
    func remarkupForMarks(_ mark: MarkCase) {
        let markdown = WF.inline(WF.t("a "), WF.t("word", mark.marks), WF.t(" b"))
        withKnownIssue("Markdown.toRemarkup splits on backticks before rewriting emphasis") {
            #expect(Markdown.toRemarkup(markdown) == mark.remarkup)
        } when: {
            mark.hasKnownToRemarkupGap
        }
    }

    @Test(arguments: RemarkupCases.marks)
    func remarkupForLinkedMarks(_ mark: MarkCase) {
        let markdown = WF.inline(WF.t("a "), WF.t("word", mark.marks, link: RemarkupCases.url), WF.t(" b"))
        withKnownIssue("Markdown.toRemarkup splits on backticks before rewriting links") {
            #expect(Markdown.toRemarkup(markdown) == mark.linkedRemarkup)
        } when: {
            mark.hasKnownLinkedToRemarkupGap
        }
    }

    @Test func blockConstructsConvert() {
        let storage = Corpus.load("# Title\n\n## Section\n\n- **a**\n- *b*\n\n> `q`\n\n```js\nlet *x* = 1;\n```")
        #expect(Markdown.toRemarkup(Corpus.write(storage)) == "= Title =\n\n== Section ==\n\n- **a**\n- //b//\n\n> ##q##\n\n```js\nlet *x* = 1;\n```")
    }

    @Test func partialMarksInsideWords() {
        let markdown = WF.inline(WF.t("pre"), WF.t("mid", .strong), WF.t("post"))
        #expect(markdown == "pre**mid**post")
        #expect(Markdown.toRemarkup(markdown) == "pre**mid**post")
    }

    @Test func emphasisNextToStrongUsesUnderscore() {
        let markdown = WF.inline(WF.t("a ", .strong), WF.t("b", [.strong, .emphasis]))
        #expect(markdown == "**a _b_**")
        #expect(Markdown.toRemarkup(markdown) == "**a //b//**")
    }

    @Test(arguments: CorpusFixtures.remarkupDrafts)
    func remarkupDraftsPassThroughUnchanged(_ sample: CorpusSample) {
        #expect(Markdown.toRemarkup(Corpus.roundTrip(sample.source, labels: true)) == Markdown.toRemarkup(sample.source))
        #expect(Markdown.toRemarkup(Corpus.roundTrip(sample.source, labels: true)) == sample.source.replacingOccurrences(of: "`inline`", with: "##inline##"))
    }

    @Test func labelsSurviveRemarkupConversion() {
        let storage = Corpus.load("{nav,  icon=file, name=Ready} *nice*", labels: true)
        #expect(Markdown.toRemarkup(Corpus.write(storage)) == "{nav,  icon=file, name=Ready} //nice//")
    }

    @Test func noEscapesAreAddedForRemarkupPunctuation() {
        let markdown = WF.inline(WF.t("a * b _ c # d [e] //f// ##g##"))
        #expect(markdown == "a * b _ c # d [e] //f// ##g##")
        #expect(!markdown.contains("\\"))
    }
}
