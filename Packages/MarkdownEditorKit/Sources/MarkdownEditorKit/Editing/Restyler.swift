import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct Restyler {
    var theme: MarkdownEditorTheme

    static let quoteIndent: CGFloat = 16
    static let listIndent: CGFloat = 36
    static let codeInset: CGFloat = 8
    static let codeEdgeSpacing: CGFloat = 8
    static let headingSpacingAfter: CGFloat = 4

    func restyleAll(_ storage: NSMutableAttributedString) {
        restyle(storage, in: NSRange(location: 0, length: storage.length))
    }

    func restyle(_ storage: NSMutableAttributedString, in range: NSRange, excluding excluded: NSRange? = nil) {
        guard storage.length > 0 else { return }
        let scan = Normalizer.clamp(range, to: storage.length)
        let fonts = FontCache()
        for paragraph in storage.markdownParagraphRanges(in: scan) where paragraph.length > 0 {
            if let excluded, Normalizer.paragraph(paragraph, intersects: excluded) { continue }
            restyleParagraph(paragraph, in: storage, fonts: fonts)
        }
    }

    private func restyleParagraph(_ paragraph: NSRange, in storage: NSMutableAttributedString, fonts: FontCache) {
        let block = storage.markdownBlock(at: paragraph.location) ?? .paragraph
        let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
        var isFirstCodeLine = false
        var isLastCodeLine = false
        if let group = block.codeGroup {
            let previous = paragraph.location > 0 ? storage.markdownBlock(at: paragraph.location - 1) : nil
            let next = NSMaxRange(paragraph) < storage.length ? storage.markdownBlock(at: NSMaxRange(paragraph)) : nil
            isFirstCodeLine = previous?.codeGroup != group
            isLastCodeLine = next?.codeGroup != group
        }
        let style = paragraphStyle(
            for: block,
            textLists: existing?.textLists ?? [],
            isFirstCodeLine: isFirstCodeLine,
            isLastCodeLine: isLastCodeLine
        )
        var styleRange = NSRange()
        let current = storage.attribute(.paragraphStyle, at: paragraph.location, longestEffectiveRange: &styleRange, in: paragraph)
        if !((current as? NSParagraphStyle)?.isEqual(style) == true && NSEqualRanges(styleRange, paragraph)) {
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
        }

        storage.enumerateAttributes(in: paragraph) { attributes, run, _ in
            let intent = attributes.markdownInlineIntent
            let isLink = attributes[.link] != nil
            let wanted = characterAttributes(for: block, intent: intent, isLink: isLink, fonts: fonts)
            Self.set(.font, wanted.font, current: attributes[.font], in: run, storage: storage)
            Self.set(.foregroundColor, wanted.color, current: attributes[.foregroundColor], in: run, storage: storage)
            Self.set(.backgroundColor, wanted.background, current: attributes[.backgroundColor], in: run, storage: storage)
            Self.set(.strikethroughStyle, wanted.strikethrough, current: attributes[.strikethroughStyle], in: run, storage: storage)
        }
    }

    private static func set(
        _ key: NSAttributedString.Key,
        _ value: NSObject?,
        current: Any?,
        in range: NSRange,
        storage: NSMutableAttributedString
    ) {
        if let value {
            if (current as? NSObject)?.isEqual(value) != true {
                storage.addAttribute(key, value: value, range: range)
            }
        } else if current != nil {
            storage.removeAttribute(key, range: range)
        }
    }

    private struct CharacterAttributes {
        var font: PlatformFont
        var color: PlatformColor
        var background: PlatformColor?
        var strikethrough: NSNumber?
    }

    private func characterAttributes(
        for block: MarkdownBlock,
        intent: MarkdownInlineIntent,
        isLink: Bool,
        fonts: FontCache
    ) -> CharacterAttributes {
        let isCodeBlock = block.isCode
        let marks = isCodeBlock ? [] : intent.intersection(.markdownMarks)
        let key = FontKey(leaf: FontKey.leafKey(block), quote: block.isInQuote, marks: marks.rawValue)
        let font = fonts.font(for: key) { self.font(for: block, intent: marks) }
        return CharacterAttributes(
            font: font,
            color: color(for: block, isLink: isLink && !isCodeBlock),
            background: marks.contains(.code) ? theme.codeBlock.fillColor : nil,
            strikethrough: marks.contains(.strikethrough) ? NSNumber(value: NSUnderlineStyle.single.rawValue) : nil
        )
    }

    func font(for block: MarkdownBlock, intent: MarkdownInlineIntent) -> PlatformFont {
        let base: PlatformFont
        switch block.leaf {
        case .code:
            return theme.monospaceFont
        case .heading(let level):
            base = theme.headingFont(level: level)
        case .paragraph, .thematicBreak, .table, .html:
            base = theme.bodyFont
        }
        var traits = base.fontTraits
        if block.isInQuote { traits.formUnion(theme.blockquote.textTraits) }
        if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
        if intent.contains(.emphasized) { traits.insert(.italic) }
        if intent.contains(.code) {
            let mono = Self.resized(theme.monospaceFont, to: base.pointSize)
            return traits.isEmpty ? mono : mono.withFontTraits(traits)
        }
        return traits == base.fontTraits ? base : base.withFontTraits(traits)
    }

    func color(for block: MarkdownBlock, isLink: Bool) -> PlatformColor {
        if isLink { return theme.linkColor }
        if block.isCode { return theme.codeBlock.textColor ?? theme.foregroundColor }
        if block.isInQuote { return theme.blockquote.textColor ?? theme.foregroundColor }
        return theme.foregroundColor
    }

    static func indent(for block: MarkdownBlock) -> CGFloat {
        var indent: CGFloat = 0
        for container in block.containers {
            switch container {
            case .quote: indent += quoteIndent
            case .listItem: indent += listIndent
            }
        }
        if block.isCode { indent += codeInset }
        return indent
    }

    func paragraphStyle(
        for block: MarkdownBlock,
        textLists: [NSTextList],
        isFirstCodeLine: Bool = false,
        isLastCodeLine: Bool = false
    ) -> NSParagraphStyle {
        let style = (theme.defaultParagraphStyle().mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.textLists = textLists
        let indent = Self.indent(for: block)
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        switch block.leaf {
        case .heading(let level):
            style.paragraphSpacingBefore = CGFloat(max(0, 7 - level)) * 2
            style.paragraphSpacing = Self.headingSpacingAfter
        case .code:
            style.paragraphSpacingBefore = isFirstCodeLine ? Self.codeEdgeSpacing : 0
            style.paragraphSpacing = isLastCodeLine ? Self.codeEdgeSpacing : 0
        case .paragraph, .thematicBreak, .table, .html:
            break
        }
        return style.copy() as? NSParagraphStyle ?? style
    }

    func typingAttributes(
        for block: MarkdownBlock,
        intent: MarkdownInlineIntent,
        paragraphStyle: NSParagraphStyle?
    ) -> [NSAttributedString.Key: Any] {
        let wanted = characterAttributes(for: block, intent: intent, isLink: false, fonts: FontCache())
        var attributes: [NSAttributedString.Key: Any] = [
            .font: wanted.font,
            .foregroundColor: wanted.color,
            .paragraphStyle: paragraphStyle ?? self.paragraphStyle(for: block, textLists: [])
        ]
        if let background = wanted.background { attributes[.backgroundColor] = background }
        if let strikethrough = wanted.strikethrough { attributes[.strikethroughStyle] = strikethrough }
        attributes.markdownBlock = block
        attributes.markdownInlineIntent = block.isCode ? intent.intersection(.softBreak) : intent
        return attributes
    }

    private static func resized(_ font: PlatformFont, to size: CGFloat) -> PlatformFont {
        guard font.pointSize != size else { return font }
        #if canImport(AppKit) && os(macOS)
        return NSFont(descriptor: font.fontDescriptor, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        return UIFont(descriptor: font.fontDescriptor, size: size)
        #endif
    }
}

private struct FontKey: Hashable {
    let leaf: Int
    let quote: Bool
    let marks: UInt

    static func leafKey(_ block: MarkdownBlock) -> Int {
        switch block.leaf {
        case .code: return -1
        case .heading(let level): return level
        case .paragraph, .thematicBreak, .table, .html: return 0
        }
    }
}

private final class FontCache {
    private var fonts: [FontKey: PlatformFont] = [:]

    func font(for key: FontKey, make: () -> PlatformFont) -> PlatformFont {
        if let cached = fonts[key] { return cached }
        let font = make()
        fonts[key] = font
        return font
    }
}
