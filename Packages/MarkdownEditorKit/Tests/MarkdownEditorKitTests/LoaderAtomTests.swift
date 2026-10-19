import Foundation
import Testing
@testable import MarkdownEditorKit
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("Loader atoms")
struct LoaderAtomTests {
    @Test(arguments: [
        "![alt *t*](i.png \"title\")",
        "![a](<with space.png>)",
        "![a](u(1).png)",
        "![it's](x.png 'q')",
        "![ref][r]",
        "![](empty.png)",
        "![nested [b]](n.png)"
    ])
    func imagesKeepByteExactSource(image: String) throws {
        let markdown = "before \(image) after\n\n[r]: https://r.png"
        let (storage, report) = LoaderFixture.load(markdown)
        #expect(report.fallbackRuns == 0)
        let paragraph = try #require(LoaderFixture.paragraphs(storage).first)
        #expect(paragraph.text == "before \u{FFFC} after")
        let attachment = try #require(storage.markdownSourceAttachment(at: 7) as? ChipTextAttachment)
        #expect(attachment.markdownSource == image)
        #expect(attachment.contentKind == AtomKind.image)
    }

    @Test func imageChipShowsAltText() throws {
        let storage = LoaderFixture.load("![a diagram](d.png) ![](e.png)").storage
        let chips = LoaderFixture.attachments(storage).compactMap { $0 as? ChipTextAttachment }
        #expect(chips.map(\.chipLabel) == ["a diagram", "image"])
        #expect(chips.map(\.markdownSource) == ["![a diagram](d.png)", "![](e.png)"])
    }

    @Test func imagesInsideLinksCarryTheLink() throws {
        let storage = LoaderFixture.load("[![img](a.png)](https://b.com)").storage
        #expect(storage.string == "\u{FFFC}")
        #expect(storage.markdownSourceAttachment(at: 0)?.markdownSource == "![img](a.png)")
        #expect(storage.markdownLink(at: 0) == "https://b.com")
    }

    @Test func inlineHTMLBecomesChips() {
        let storage = LoaderFixture.load("x <b>y</b> <br/> z").storage
        #expect(storage.string == "x \u{FFFC}y\u{FFFC} \u{FFFC} z")
        let atoms = LoaderFixture.attachments(storage)
        #expect(atoms.map(\.markdownSource) == ["<b>", "</b>", "<br/>"])
        #expect(atoms.allSatisfy { $0.contentKind == AtomKind.inlineHTML })
    }

    @Test func tableSourceIsByteExactAndCellsAreParsed() throws {
        let markdown = "| a | **b** |\n|:--|--:|\n| 1 | `two` |\n|  | x \\| y |"
        let storage = LoaderFixture.load("intro\n\n\(markdown)\n\nafter").storage
        let paragraphs = LoaderFixture.paragraphs(storage)
        #expect(paragraphs.map(\.leaf) == [.paragraph, .table, .paragraph])
        let table = try #require(storage.markdownSourceAttachment(at: paragraphs[1].range.location) as? TableAttachment)
        #expect(table.markdownSource == markdown)
        #expect(table.rows.map { $0.map(\.string) } == [["a", "b"], ["1", "two"], ["", "x | y"]])
        #expect(table.alignments == [.left, .right])
        #expect(table.rows[0][1].markdownInlineIntent(at: 0) == .stronglyEmphasized)
        #expect(table.rows[1][1].markdownInlineIntent(at: 0) == .code)
    }

    @Test func tableSourceExtendsOverEmptyTrailingRows() throws {
        let markdown = "| a |\n|---|\n| 1 |\n| |"
        let storage = LoaderFixture.load(markdown).storage
        let table = try #require(storage.markdownSourceAttachment(at: 0) as? TableAttachment)
        #expect(table.markdownSource == markdown)
    }

    @Test(arguments: [
        ("> | a |\n> |---|\n> | 1 |", "q"),
        ("- | a |\n  |---|\n  | 1 |", "l"),
        ("- intro\n\n  | a |\n  |---|\n  | 1 |", "l"),
        ("> - | a |\n>   |---|\n>   | 1 |", "ql")
    ])
    func tableSourceDropsContainerPrefixes(markdown: String, expectedShape: String) throws {
        let storage = LoaderFixture.load(markdown).storage
        let paragraph = try #require(LoaderFixture.paragraphs(storage).last)
        #expect(paragraph.leaf == .table)
        #expect(shape(of: paragraph.containers) == expectedShape)
        let table = try #require(storage.markdownSourceAttachment(at: paragraph.range.location))
        #expect(table.markdownSource == "| a |\n|---|\n| 1 |")
    }

    @Test func tableLayoutFitsTheAvailableWidth() throws {
        let storage = LoaderFixture.load("| first column | second column with long text |\n|---|---|\n| 1 | 2 |").storage
        let table = try #require(storage.markdownSourceAttachment(at: 0) as? TableAttachment)
        let wide = table.layout(availableWidth: 2000)
        #expect(wide.columnWidths.count == 2)
        #expect(wide.rowHeights.count == 2)
        #expect(wide.size.width < 2000)
        let narrow = table.layout(availableWidth: 120)
        #expect(narrow.size.width <= 120 + 1)
        #expect(narrow.size.height > wide.size.height)
        let bounds = table.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 20),
            glyphPosition: .zero,
            characterIndex: 0
        )
        #expect(bounds.width > 0 && bounds.width <= 302)
        #expect(bounds.height > 0)
        #expect(table.image(forBounds: bounds, textContainer: nil, characterIndex: 0) != nil)
    }

    @Test func htmlBlocksKeepVerbatimSource() throws {
        let html = "<details>\n<summary>More</summary>\n\nBody\n</details>"
        let storage = LoaderFixture.load("para\n\n<div class=\"x\">\n  <p>hi</p>\n</div>\n\n\(html)").storage
        let atoms = LoaderFixture.attachments(storage)
        #expect(atoms.allSatisfy { $0 is HTMLBlockAttachment })
        #expect(atoms.first?.markdownSource == "<div class=\"x\">\n  <p>hi</p>\n</div>")
        #expect(atoms.first?.contentKind == AtomKind.htmlBlock)
        #expect(LoaderFixture.paragraphs(storage).first?.text == "para")
    }

    @Test @MainActor func htmlBlocksRenderImportedContent() throws {
        let attachment = HTMLBlockAttachment(markdownSource: "<div><b>bold</b> text</div>")
        let rendered = attachment.renderedContent
        #expect(rendered.string.contains("bold"))
        #expect(!rendered.string.contains("<b>"))
        let bounds = attachment.attachmentBounds(
            for: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 300, height: 20),
            glyphPosition: .zero,
            characterIndex: 0
        )
        #expect(bounds.height > 0)
        #expect(attachment.image(forBounds: bounds, textContainer: nil, characterIndex: 0) != nil)
    }

    @Test func thematicBreakIsAHorizontalRuleAttachment() throws {
        let storage = LoaderFixture.load("a\n\n___\n\nb").storage
        let rule = try #require(storage.markdownSourceAttachment(at: 2) as? HorizontalRuleAttachment)
        #expect(rule.markdownSource == "___")
        #expect(storage.markdownBlock(at: 2)?.leaf == .thematicBreak)
        #expect(storage.markdownBlock(at: 2)?.isAtom == true)
    }

    @Test func atomParagraphsHoldOneObjectReplacementCharacter() {
        let storage = LoaderFixture.load("***\n\n| a |\n|---|\n\n<div>x</div>").storage
        let paragraphs = LoaderFixture.paragraphs(storage)
        #expect(paragraphs.map(\.text) == ["\u{FFFC}", "\u{FFFC}", "\u{FFFC}"])
        #expect(paragraphs.map(\.leaf) == [.thematicBreak, .table, .html])
        #expect(paragraphs.allSatisfy { storage.markdownInlineIntent(at: $0.range.location).isEmpty })
    }
}
