import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum Operations {

    /// Replace `range` with plain `text`, inheriting paragraph attributes
    /// from the character at `range.location` so the inserted text continues
    /// the surrounding block (paragraph, list item, blockquote, etc.).
    @discardableResult
    public static func insertText(
        in storage: NSTextStorage,
        replacing range: NSRange,
        with text: String
    ) -> NSRange {
        let safe = clampedRange(range, in: storage.length)
        let attrs = inheritedAttributes(in: storage, at: safe.location)
        let attributed = NSAttributedString(string: text, attributes: attrs)
        storage.beginEditing()
        storage.replaceCharacters(in: safe, with: attributed)
        storage.endEditing()
        return NSRange(location: safe.location + (text as NSString).length, length: 0)
    }

    /// Replace `range` with a link rendered as `label` text carrying a `.link`
    /// attribute. The serializer emits `[label](url)` from this. Inherits
    /// surrounding paragraph attributes.
    @discardableResult
    public static func insertLink(
        in storage: NSTextStorage,
        replacing range: NSRange,
        label: String,
        url: String,
        theme: MarginaliaTheme
    ) -> NSRange {
        let safe = clampedRange(range, in: storage.length)
        var attrs = inheritedAttributes(in: storage, at: safe.location)
        attrs[.link] = url
        attrs[.marginaliaLink] = url
        attrs[.foregroundColor] = theme.linkColor
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        attrs[.marginaliaInline] = InlineTag.link
        let attributed = NSMutableAttributedString(string: label, attributes: attrs)
        storage.beginEditing()
        storage.replaceCharacters(in: safe, with: attributed)
        // Append a single space after the link so a follow-on character the
        // user types isn't auto-linked. Inherits the paragraph attributes
        // but drops link-specific ones.
        var trailing = inheritedAttributes(in: storage, at: safe.location)
        trailing.removeValue(forKey: .link)
        trailing.removeValue(forKey: .marginaliaLink)
        trailing.removeValue(forKey: .underlineStyle)
        trailing.removeValue(forKey: .marginaliaInline)
        let trailingSpace = NSAttributedString(string: " ", attributes: trailing)
        let trailingLocation = safe.location + (label as NSString).length
        storage.replaceCharacters(in: NSRange(location: trailingLocation, length: 0), with: trailingSpace)
        storage.endEditing()
        let cursor = trailingLocation + 1
        return NSRange(location: cursor, length: 0)
    }

    // MARK: - block-level operations
    //
    // These transform the markdown form of the affected paragraph(s),
    // recompile through the supplied compiler, and replace the storage
    // range. Going through markdown keeps the styling logic in one place
    // (the compiler) instead of duplicating font/paragraph-style updates
    // here. The cost is a small re-parse per action — fine because the
    // compiler operates on at most a few paragraphs of source.

    @discardableResult
    public static func setHeading(
        in storage: NSTextStorage,
        range: NSRange,
        level: Int,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            transformHeading(md, level: level)
        }
    }

    @discardableResult
    public static func toggleUnorderedList(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            transformList(md, kind: .bullet)
        }
    }

    @discardableResult
    public static func toggleOrderedList(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            transformList(md, kind: .ordered)
        }
    }

    @discardableResult
    public static func toggleTaskList(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            transformList(md, kind: .task)
        }
    }

    @discardableResult
    public static func toggleBlockquote(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            transformBlockquote(md)
        }
    }

    @discardableResult
    public static func insertCodeBlock(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            wrapInCodeFence(md)
        }
    }

    @discardableResult
    public static func indent(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            transformIndent(md)
        }
    }

    @discardableResult
    public static func outdent(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            transformOutdent(md)
        }
    }

    @discardableResult
    public static func insertHorizontalRule(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange {
        mutateBlocks(
            in: storage, range: range, compiler: compiler, serializer: serializer,
            dialect: dialect, mode: mode, theme: theme
        ) { md in
            md + "\n---\n"
        }
    }

    /// Round-trip the paragraph(s) covered by `range` through markdown,
    /// applying `transform` to the markdown form, then replace the affected
    /// storage with the recompiled result.
    private static func mutateBlocks(
        in storage: NSTextStorage,
        range: NSRange,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme,
        transform: (String) -> String
    ) -> NSRange {
        let safe = clampedRange(range, in: storage.length)
        let ns = storage.string as NSString
        let lineRange = ns.paragraphRange(for: safe)
        let para = storage.attributedSubstring(from: lineRange)
        let md = serializer.serialize(para, dialect: dialect)
        let newMd = transform(md)
        let newAttr = compiler.compile(newMd, dialect: dialect, mode: mode, theme: theme)
        storage.beginEditing()
        storage.replaceCharacters(in: lineRange, with: newAttr)
        storage.endEditing()
        // Keep the cursor on the styled line by landing it just before the
        // trailing newline. Otherwise the user types into the *next*
        // paragraph instead of continuing to edit what they just headed /
        // listed / quoted.
        let endOfLine = lineRange.location + newAttr.length
        let cursor = max(lineRange.location, endOfLine - 1)
        return NSRange(location: cursor, length: 0)
    }

    // MARK: - markdown transforms

    private static func transformHeading(_ md: String, level: Int) -> String {
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let stripped = lines.map(stripLeadingHeadingPrefix)
        let prefix = level == 0 ? "" : String(repeating: "#", count: max(1, min(6, level))) + " "
        let result = stripped.map { line -> String in
            line.isEmpty ? line : prefix + line
        }
        return result.joined(separator: "\n")
    }

    private static func stripLeadingHeadingPrefix(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#) else { return line }
        let ns = line as NSString
        let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        guard let m else { return line }
        return ns.substring(from: m.range.upperBound)
    }

    private enum ListMarkerKind { case bullet, ordered, task }

    private static func transformList(_ md: String, kind: ListMarkerKind) -> String {
        let rawLines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Treat an empty input as "the user wants a list line right here" —
        // otherwise clicking the bullet button on an empty editor does
        // nothing.
        let lines = rawLines.isEmpty ? [""] : rawLines
        let allEmpty = lines.allSatisfy { $0.isEmpty }
        let allMatch = lines.allSatisfy { line in
            line.isEmpty || lineHasListMarker(line, kind: kind)
        }
        if allMatch && !allEmpty {
            return lines.map(stripListMarker).joined(separator: "\n")
        }
        let prefix: (Int) -> String = { idx in
            switch kind {
            case .bullet: return "- "
            case .ordered: return "\(idx). "
            case .task: return "- [ ] "
            }
        }
        var counter = 1
        let stripped = lines.map(stripListMarker)
        let result = stripped.enumerated().map { idx, line -> String in
            // Empty paragraph: still inject a marker on the first blank
            // line so the toolbar action visibly creates a list item.
            if line.isEmpty {
                if allEmpty && idx == 0 {
                    defer { if kind == .ordered { counter += 1 } }
                    return prefix(counter)
                }
                return line
            }
            defer { if kind == .ordered { counter += 1 } }
            return prefix(counter) + line
        }
        return result.joined(separator: "\n")
    }

    private static func lineHasListMarker(_ line: String, kind: ListMarkerKind) -> Bool {
        let pattern: String
        switch kind {
        case .bullet: pattern = #"^\s*[-*+]\s+"#
        case .ordered: pattern = #"^\s*\d+[.)]\s+"#
        case .task: pattern = #"^\s*[-*+]\s+\[[ xX]\]\s+"#
        }
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func stripListMarker(_ line: String) -> String {
        let patterns = [#"^\s*[-*+]\s+\[[ xX]\]\s+"#, #"^\s*[-*+]\s+"#, #"^\s*\d+[.)]\s+"#]
        for p in patterns {
            if let r = line.range(of: p, options: .regularExpression) {
                return String(line[r.upperBound...])
            }
        }
        return line
    }

    private static func transformBlockquote(_ md: String) -> String {
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let allQuoted = lines.allSatisfy { $0.isEmpty || $0.hasPrefix("> ") || $0 == ">" }
        if allQuoted && !lines.allSatisfy({ $0.isEmpty }) {
            return lines.map { line -> String in
                if line.hasPrefix("> ") { return String(line.dropFirst(2)) }
                if line == ">" { return "" }
                return line
            }.joined(separator: "\n")
        }
        return lines.map { line -> String in
            line.isEmpty ? ">" : "> " + line
        }.joined(separator: "\n")
    }

    private static func transformIndent(_ md: String) -> String {
        md.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                line.isEmpty ? String(line) : "  " + String(line)
            }
            .joined(separator: "\n")
    }

    private static func transformOutdent(_ md: String) -> String {
        md.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let s = String(line)
                if s.hasPrefix("  ") { return String(s.dropFirst(2)) }
                if s.hasPrefix("\t") { return String(s.dropFirst()) }
                return s
            }
            .joined(separator: "\n")
    }

    private static func wrapInCodeFence(_ md: String) -> String {
        var trimmed = md
        while trimmed.hasSuffix("\n") { trimmed.removeLast() }
        if trimmed.isEmpty { trimmed = "code" }
        return "```\n" + trimmed + "\n```"
    }

    // MARK: - inline format toggles

    @discardableResult
    public static func toggleBold(
        in storage: NSTextStorage,
        range: NSRange,
        theme: MarginaliaTheme
    ) -> NSRange {
        toggleFontTrait(in: storage, range: range, trait: .bold, theme: theme, placeholder: "bold")
    }

    @discardableResult
    public static func toggleItalic(
        in storage: NSTextStorage,
        range: NSRange,
        theme: MarginaliaTheme
    ) -> NSRange {
        toggleFontTrait(in: storage, range: range, trait: .italic, theme: theme, placeholder: "italic")
    }

    @discardableResult
    public static func toggleStrikethrough(
        in storage: NSTextStorage,
        range: NSRange,
        theme: MarginaliaTheme
    ) -> NSRange {
        if range.length == 0 {
            return insertStyledPlaceholder(
                in: storage,
                at: range.location,
                placeholder: "strike",
                theme: theme
            ) { attrs in
                var a = attrs
                a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                return a
            }
        }
        let safe = clampedRange(range, in: storage.length)
        let allOn = isUniformAttribute(in: storage, range: safe, key: .strikethroughStyle) { value in
            (value as? Int).map { $0 != 0 } ?? false
        }
        storage.beginEditing()
        if allOn {
            storage.removeAttribute(.strikethroughStyle, range: safe)
        } else {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: safe)
        }
        storage.endEditing()
        return safe
    }

    @discardableResult
    public static func toggleCodeSpan(
        in storage: NSTextStorage,
        range: NSRange,
        theme: MarginaliaTheme
    ) -> NSRange {
        if range.length == 0 {
            return insertStyledPlaceholder(
                in: storage,
                at: range.location,
                placeholder: "code",
                theme: theme
            ) { attrs in
                var a = attrs
                a[.font] = theme.monospaceFont
                a[.marginaliaInline] = InlineTag.codeSpan
                a[.backgroundColor] = subtleCodeBackground(theme: theme)
                return a
            }
        }
        let safe = clampedRange(range, in: storage.length)
        let allOn = isUniformAttribute(in: storage, range: safe, key: .marginaliaInline) { value in
            (value as? InlineTag) == .codeSpan
        }
        storage.beginEditing()
        if allOn {
            storage.removeAttribute(.marginaliaInline, range: safe)
            storage.removeAttribute(.backgroundColor, range: safe)
            storage.addAttribute(.font, value: theme.bodyFont, range: safe)
        } else {
            storage.addAttribute(.marginaliaInline, value: InlineTag.codeSpan, range: safe)
            storage.addAttribute(.font, value: theme.monospaceFont, range: safe)
            storage.addAttribute(.backgroundColor, value: subtleCodeBackground(theme: theme), range: safe)
        }
        storage.endEditing()
        return safe
    }

    // MARK: - private toggle helpers

    private enum FontTrait { case bold, italic }

    private static func toggleFontTrait(
        in storage: NSTextStorage,
        range: NSRange,
        trait: FontTrait,
        theme: MarginaliaTheme,
        placeholder: String
    ) -> NSRange {
        if range.length == 0 {
            return insertStyledPlaceholder(
                in: storage,
                at: range.location,
                placeholder: placeholder,
                theme: theme
            ) { attrs in
                var a = attrs
                let baseFont = (a[.font] as? PlatformFont) ?? theme.bodyFont
                a[.font] = applyTrait(trait, on: baseFont, enable: true)
                return a
            }
        }
        let safe = clampedRange(range, in: storage.length)
        let allOn = isUniformFontTrait(in: storage, range: safe, trait: trait)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: safe) { value, subRange, _ in
            let base = (value as? PlatformFont) ?? theme.bodyFont
            let updated = applyTrait(trait, on: base, enable: !allOn)
            storage.addAttribute(.font, value: updated, range: subRange)
        }
        storage.endEditing()
        return safe
    }

    private static func insertStyledPlaceholder(
        in storage: NSTextStorage,
        at location: Int,
        placeholder: String,
        theme: MarginaliaTheme,
        styling: (inout [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]
    ) -> NSRange {
        let safe = max(0, min(location, storage.length))
        var attrs = inheritedAttributes(in: storage, at: safe)
        attrs = styling(&attrs)
        let inserted = NSAttributedString(string: placeholder, attributes: attrs)
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: safe, length: 0), with: inserted)
        storage.endEditing()
        return NSRange(location: safe, length: (placeholder as NSString).length)
    }

    private static func isUniformFontTrait(
        in storage: NSTextStorage,
        range: NSRange,
        trait: FontTrait
    ) -> Bool {
        var allOn = true
        var sawAny = false
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            sawAny = true
            let font = value as? PlatformFont
            if font == nil || !hasTrait(trait, on: font!) {
                allOn = false
                stop.pointee = true
            }
        }
        return sawAny && allOn
    }

    private static func isUniformAttribute(
        in storage: NSTextStorage,
        range: NSRange,
        key: NSAttributedString.Key,
        predicate: (Any?) -> Bool
    ) -> Bool {
        var allOn = true
        var sawAny = false
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            sawAny = true
            if !predicate(value) {
                allOn = false
                stop.pointee = true
            }
        }
        return sawAny && allOn
    }

    private static func subtleCodeBackground(theme: MarginaliaTheme) -> PlatformColor {
        #if canImport(AppKit) && os(macOS)
        return NSColor.tertiaryLabelColor.withAlphaComponent(0.12)
        #else
        return UIColor.tertiaryLabel.withAlphaComponent(0.12)
        #endif
    }

    // MARK: - helpers

    private static func clampedRange(_ range: NSRange, in length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let remaining = max(0, length - location)
        return NSRange(location: location, length: max(0, min(range.length, remaining)))
    }

    private static func hasTrait(_ trait: FontTrait, on font: PlatformFont) -> Bool {
        #if canImport(AppKit) && os(macOS)
        let symbolic = font.fontDescriptor.symbolicTraits
        switch trait {
        case .bold: return symbolic.contains(.bold)
        case .italic: return symbolic.contains(.italic)
        }
        #else
        let symbolic = font.fontDescriptor.symbolicTraits
        switch trait {
        case .bold: return symbolic.contains(.traitBold)
        case .italic: return symbolic.contains(.traitItalic)
        }
        #endif
    }

    private static func applyTrait(_ trait: FontTrait, on font: PlatformFont, enable: Bool) -> PlatformFont {
        #if canImport(AppKit) && os(macOS)
        var symbolic = font.fontDescriptor.symbolicTraits
        let toggle: NSFontDescriptor.SymbolicTraits = (trait == .bold) ? .bold : .italic
        if enable { symbolic.insert(toggle) } else { symbolic.remove(toggle) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #else
        var symbolic = font.fontDescriptor.symbolicTraits
        let toggle: UIFontDescriptor.SymbolicTraits = (trait == .bold) ? .traitBold : .traitItalic
        if enable { symbolic.insert(toggle) } else { symbolic.remove(toggle) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(symbolic) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
        #endif
    }

    /// Read the attributes at `location` to seed inserted text. If the
    /// storage is empty or location is at the very end, fall back to a
    /// minimal paragraph style.
    private static func inheritedAttributes(
        in storage: NSTextStorage,
        at location: Int
    ) -> [NSAttributedString.Key: Any] {
        let safe = max(0, min(location, storage.length))
        if storage.length == 0 {
            return [:]
        }
        let probe = (safe >= storage.length) ? storage.length - 1 : safe
        let raw = storage.attributes(at: probe, effectiveRange: nil)
        // Strip inline-only adornments — link/code-span etc. should not
        // leak into newly-typed plain text.
        var carry: [NSAttributedString.Key: Any] = [:]
        for key in [
            NSAttributedString.Key.font,
            .foregroundColor,
            .paragraphStyle,
            .marginaliaBlock,
            .marginaliaListItem
        ] {
            if let v = raw[key] { carry[key] = v }
        }
        return carry
    }
}
