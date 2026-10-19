import Foundation
import Testing
@testable import MarkdownEditorKit
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct LoadedParagraph {
    let range: NSRange
    let text: String
    let block: MarkdownBlock?
    let lists: [NSTextList]

    var leaf: MarkdownBlock.Leaf? { block?.leaf }
    var containers: [MarkdownBlock.Container] { block?.containers ?? [] }
}

enum LoaderFixture {
    static func load(
        _ markdown: String,
        rules: [InlineContentRule] = [],
        provider: InlineContentProvider? = nil
    ) -> (storage: NSMutableAttributedString, report: LoaderReport) {
        MarkdownLoader(inlineContentRules: rules, inlineContentProvider: provider).loadWithReport(markdown)
    }

    static func paragraphs(_ storage: NSAttributedString) -> [LoadedParagraph] {
        let ns = storage.string as NSString
        return storage.markdownParagraphRanges().compactMap { range in
            guard range.length > 0 else { return nil }
            var content = range
            if ns.character(at: NSMaxRange(range) - 1) == MarkdownParagraph.separator {
                content.length -= 1
            }
            let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            return LoadedParagraph(
                range: content,
                text: ns.substring(with: content),
                block: storage.markdownBlock(at: range.location),
                lists: style?.textLists ?? []
            )
        }
    }

    static func texts(_ markdown: String) -> [String] {
        paragraphs(load(markdown).storage).map(\.text)
    }

    static func literals(_ storage: NSAttributedString) -> [String] {
        var out: [String] = []
        storage.enumerateAttribute(
            .markdownLiteral,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard let source = value as? String else { return }
            out.append((storage.string as NSString).substring(with: range) + "=" + source)
        }
        return out
    }

    static func intentRuns(_ storage: NSAttributedString, in range: NSRange? = nil) -> [(String, MarkdownInlineIntent)] {
        var out: [(String, MarkdownInlineIntent)] = []
        let ns = storage.string as NSString
        let scan = range ?? NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.markdownInlineIntent, in: scan) { value, range, _ in
            out.append((ns.substring(with: range), MarkdownInlineIntent(attributeValue: value) ?? []))
        }
        return out
    }

    static func attachments(_ storage: NSAttributedString) -> [any MarkdownSourceAttachment] {
        var out: [any MarkdownSourceAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? (NSTextAttachment & MarkdownSourceAttachment) {
                out.append(attachment)
            }
        }
        return out
    }

    static func blockIsUniform(_ storage: NSAttributedString) -> Bool {
        for paragraph in storage.markdownParagraphRanges() where paragraph.length > 0 {
            var effective = NSRange()
            guard storage.attribute(
                .markdownBlock,
                at: paragraph.location,
                longestEffectiveRange: &effective,
                in: paragraph
            ) is MarkdownBlock,
                  NSIntersectionRange(effective, paragraph) == paragraph
            else { return false }
        }
        return true
    }
}
