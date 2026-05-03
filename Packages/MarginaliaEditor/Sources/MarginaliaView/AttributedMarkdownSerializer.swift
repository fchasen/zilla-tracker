import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class AttributedMarkdownSerializer {

    public typealias Dialect = MarginaliaView.Dialect

    public init() {}

    public func serialize(_ attributed: NSAttributedString, dialect: Dialect) -> String {
        let total = attributed.length
        guard total > 0 else { return "" }
        var out = ""
        var emittedSomething = false
        var cursor = 0

        while cursor < total {
            let blockAttr = attributed.attribute(.marginaliaBlock, at: cursor, effectiveRange: nil) as? BlockAttribute
            // Compute the contiguous range with the same identity (matched
            // BlockAttribute pointer or equal struct). enumerateAttribute is
            // simpler — build the range by scanning forward.
            var blockEnd = total
            attributed.enumerateAttribute(.marginaliaBlock, in: NSRange(location: cursor, length: total - cursor)) { value, range, stop in
                if range.location == cursor {
                    let next = (value as? BlockAttribute)
                    if next === blockAttr || (next == blockAttr) {
                        // continue
                    }
                } else {
                    blockEnd = range.location
                    stop.pointee = true
                }
            }

            let blockRange = NSRange(location: cursor, length: blockEnd - cursor)
            if let blockAttr = blockAttr {
                if emittedSomething { out.append("\n") }
                out.append(emitBlock(blockAttr, attributed: attributed, range: blockRange, dialect: dialect))
            } else {
                // Untagged region — emit as plain text.
                if emittedSomething { out.append("\n") }
                let plain = attributed.attributedSubstring(from: blockRange).string
                out.append(plain)
            }
            emittedSomething = true
            cursor = blockEnd
        }
        return ensureTrailingNewline(out)
    }

    // MARK: - block emission

    private func emitBlock(
        _ block: BlockAttribute,
        attributed: NSAttributedString,
        range: NSRange,
        dialect: Dialect
    ) -> String {
        let inner = inlineMarkdown(of: attributed, range: range, dialect: dialect, in: block)
        let trimmed = stripOneTrailingNewline(inner)
        let blockquotePrefix = String(repeating: "> ", count: max(0, block.blockquoteDepth))

        switch block.tag {
        case .heading:
            let level = max(1, min(6, block.level))
            let prefix = String(repeating: "#", count: level) + " "
            return prefixLines(blockquotePrefix + prefix + trimmed, with: "")
        case .paragraph:
            return prefixLines(trimmed, with: blockquotePrefix)
        case .blockquote:
            return prefixLines(trimmed, with: blockquotePrefix)
        case .unorderedListItem:
            let listAttr = attributed.attribute(.marginaliaListItem, at: range.location, effectiveRange: nil) as? ListItemAttribute
            let level = listAttr?.level ?? 0
            let indent = String(repeating: "  ", count: max(0, level))
            return blockquotePrefix + indent + "- " + trimmed
        case .orderedListItem:
            let listAttr = attributed.attribute(.marginaliaListItem, at: range.location, effectiveRange: nil) as? ListItemAttribute
            let level = listAttr?.level ?? 0
            let index = listAttr?.orderedIndex ?? 1
            let indent = String(repeating: "  ", count: max(0, level))
            return blockquotePrefix + indent + "\(index). " + trimmed
        case .taskListItem:
            let listAttr = attributed.attribute(.marginaliaListItem, at: range.location, effectiveRange: nil) as? ListItemAttribute
            let level = listAttr?.level ?? 0
            let checked = listAttr?.isChecked ?? false
            let indent = String(repeating: "  ", count: max(0, level))
            return blockquotePrefix + indent + "- [\(checked ? "x" : " ")] " + trimmed
        case .fencedCode:
            let lang = block.language ?? ""
            let body = stripOneTrailingNewline(attributed.attributedSubstring(from: range).string)
            // Compiler emitted the original fence text verbatim; if the body
            // already starts with ``` keep it. Otherwise wrap.
            if body.hasPrefix("```") || body.hasPrefix("~~~") {
                return body
            }
            return "```\(lang)\n" + body + "\n```"
        case .indentedCode:
            let body = stripOneTrailingNewline(attributed.attributedSubstring(from: range).string)
            return body
        case .horizontalRule:
            return "---"
        case .htmlBlock, .linkReferenceDefinition, .pipeTable:
            return stripOneTrailingNewline(attributed.attributedSubstring(from: range).string)
        }
    }

    // MARK: - inline run emission

    private func inlineMarkdown(of attributed: NSAttributedString, range: NSRange, dialect: Dialect, in block: BlockAttribute) -> String {
        var out = ""
        var cursor = range.location
        let end = range.location + range.length
        while cursor < end {
            var runRange = NSRange(location: cursor, length: 0)
            let attrs = attributed.attributes(at: cursor, longestEffectiveRange: &runRange, in: NSRange(location: cursor, length: end - cursor))
            let runText = (attributed.string as NSString).substring(with: runRange)
            out.append(emitInlineRun(text: runText, attrs: attrs, dialect: dialect, in: block))
            cursor = runRange.location + runRange.length
        }
        return out
    }

    /// Traits that the block-level paragraph styling already implies, so the
    /// serializer doesn't double them with explicit inline markers.
    private func paragraphImpliedBold(for block: BlockAttribute) -> Bool {
        block.tag == .heading
    }

    private func emitInlineRun(
        text: String,
        attrs: [NSAttributedString.Key: Any],
        dialect: Dialect,
        in block: BlockAttribute
    ) -> String {
        // Skip lone newlines so they're emitted by the block-level joiner.
        if text == "\n" { return "\n" }

        // Attachment runs round-trip via their host metadata; skip the
        // `\u{FFFC}` placeholder text so it doesn't appear in markdown.
        // Block-level emit (e.g. task list `[x]` prefix) re-emits the
        // attachment-derived markdown above.
        if attrs[.attachment] != nil {
            return ""
        }
        // List markers (bullet glyph, ordered number) are rendered into
        // storage so the user sees them; the block-level emit re-creates
        // them in markdown form, so skip the visual run here.
        if let flag = attrs[.marginaliaListMarker] as? Bool, flag {
            return ""
        }

        var content = text
        var prefix = ""
        var suffix = ""

        // Link
        if let url = (attrs[.marginaliaLink] as? String) ?? linkURLString(from: attrs[.link]) {
            let label = stripTrailingNewline(content)
            switch dialect {
            case .commonMark:
                return "[\(label)](\(url))"
            case .remarkup:
                return "[[\(url) | \(label)]]"
            }
        }

        // Code span — detected via the inline tag the compiler sets so we
        // don't have to second-guess font-trait detection across platforms.
        if let inline = attrs[.marginaliaInline] as? InlineTag, inline == .codeSpan {
            let label = stripTrailingNewline(content)
            return "`\(label)`"
        }
        if let font = attrs[.font] as? PlatformFont, isMonospace(font) {
            let label = stripTrailingNewline(content)
            return "`\(label)`"
        }

        // Bold / italic via font traits. Heading-paragraph bold is implied
        // by the block style and must not be re-emitted as `**…**`.
        if let font = attrs[.font] as? PlatformFont {
            let traits = symbolicTraits(of: font)
            let bold = isBold(traits) && !paragraphImpliedBold(for: block)
            let italic = isItalic(traits)
            if bold && italic {
                prefix = "***"; suffix = "***"
            } else if bold {
                prefix = "**"; suffix = "**"
            } else if italic {
                switch dialect {
                case .commonMark: prefix = "*"; suffix = "*"
                case .remarkup: prefix = "//"; suffix = "//"
                }
            }
        }

        // Strikethrough
        if let style = attrs[.strikethroughStyle] as? Int, style != 0 {
            prefix = "~~" + prefix
            suffix = suffix + "~~"
        }

        // Trim trailing newline so wrappers don't surround it.
        let (body, tail) = splitTrailingNewline(content)
        content = body
        return prefix + content + suffix + tail
    }

    // MARK: - helpers

    private func stripOneTrailingNewline(_ s: String) -> String {
        if s.hasSuffix("\n") { return String(s.dropLast()) }
        return s
    }

    private func stripTrailingNewline(_ s: String) -> String {
        var out = s
        while out.hasSuffix("\n") { out.removeLast() }
        return out
    }

    private func splitTrailingNewline(_ s: String) -> (String, String) {
        if s.hasSuffix("\n") { return (String(s.dropLast()), "\n") }
        return (s, "")
    }

    private func ensureTrailingNewline(_ s: String) -> String {
        if s.isEmpty { return "" }
        if s.hasSuffix("\n") { return s }
        return s + "\n"
    }

    private func prefixLines(_ s: String, with prefix: String) -> String {
        guard !prefix.isEmpty else { return s }
        return s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + String($0) }
            .joined(separator: "\n")
    }

    private func linkURLString(from any: Any?) -> String? {
        if let url = any as? URL { return url.absoluteString }
        if let s = any as? String { return s }
        return nil
    }

    private func isMonospace(_ font: PlatformFont) -> Bool {
        #if canImport(AppKit) && os(macOS)
        return font.fontDescriptor.symbolicTraits.contains(NSFontDescriptor.SymbolicTraits.monoSpace)
        #else
        return font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
        #endif
    }

    #if canImport(AppKit) && os(macOS)
    private func symbolicTraits(of font: PlatformFont) -> NSFontDescriptor.SymbolicTraits {
        font.fontDescriptor.symbolicTraits
    }
    private func isBold(_ traits: NSFontDescriptor.SymbolicTraits) -> Bool {
        traits.contains(.bold)
    }
    private func isItalic(_ traits: NSFontDescriptor.SymbolicTraits) -> Bool {
        traits.contains(.italic)
    }
    #else
    private func symbolicTraits(of font: PlatformFont) -> UIFontDescriptor.SymbolicTraits {
        font.fontDescriptor.symbolicTraits
    }
    private func isBold(_ traits: UIFontDescriptor.SymbolicTraits) -> Bool {
        traits.contains(.traitBold)
    }
    private func isItalic(_ traits: UIFontDescriptor.SymbolicTraits) -> Bool {
        traits.contains(.traitItalic)
    }
    #endif
}
