import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum InsertNewline {

    /// If the cursor sits on a list-item paragraph, intercept the newline:
    /// non-empty items grow a fresh sibling marker; empty items terminate
    /// the list (the line drops back to a plain paragraph). Returns the
    /// post-edit selection if it consumed the newline, `nil` to let the
    /// text view handle it normally.
    @discardableResult
    public static func handle(
        in storage: NSTextStorage,
        cursor: Int,
        compiler: MarkdownAttributedCompiler,
        serializer: AttributedMarkdownSerializer,
        dialect: Dialect,
        mode: Mode,
        theme: MarginaliaTheme
    ) -> NSRange? {
        let ns = storage.string as NSString
        guard cursor >= 0, cursor <= ns.length, ns.length > 0 else { return nil }
        let probe = max(0, min(cursor, ns.length - 1))
        guard let _ = storage.attribute(.marginaliaListItem, at: probe, effectiveRange: nil) as? ListItemAttribute else {
            return nil
        }
        let lineRange = ns.paragraphRange(for: NSRange(location: probe, length: 0))
        let para = storage.attributedSubstring(from: lineRange)
        let md = serializer.serialize(para, dialect: dialect)
        let line = trimTrailingNewlines(md)

        if isEmptyListLine(line) {
            // Strip the marker; the line becomes a plain blank paragraph.
            let replacement = compiler.compile("\n", dialect: dialect, mode: mode, theme: theme)
            storage.beginEditing()
            storage.replaceCharacters(in: lineRange, with: replacement)
            storage.endEditing()
            return NSRange(location: lineRange.location, length: 0)
        }

        let nextMarker = nextListMarker(forLine: line)
        let combined = line + "\n" + nextMarker + "\n"
        let replacement = compiler.compile(combined, dialect: dialect, mode: mode, theme: theme)
        storage.beginEditing()
        storage.replaceCharacters(in: lineRange, with: replacement)
        storage.endEditing()
        // Cursor at end of the new (empty) list-item line — that's one
        // character before the trailing newline.
        let cursorAt = lineRange.location + replacement.length - 1
        return NSRange(location: max(lineRange.location, cursorAt), length: 0)
    }

    // MARK: - line helpers

    private static func trimTrailingNewlines(_ s: String) -> String {
        var out = s
        while out.hasSuffix("\n") { out.removeLast() }
        return out
    }

    private static func isEmptyListLine(_ line: String) -> Bool {
        line.range(
            of: #"^\s*([-*+]|\d+[.)])\s*(\[[ xX]\]\s*)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func nextListMarker(forLine line: String) -> String {
        if line.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil {
            let leading = leadingWhitespace(of: line)
            return leading + "- [ ] "
        }
        if let m = try? NSRegularExpression(pattern: #"^(\s*)(\d+)[.)]\s+"#)
            .firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let ns = line as NSString
            let leading = ns.substring(with: m.range(at: 1))
            let index = Int(ns.substring(with: m.range(at: 2))) ?? 0
            return "\(leading)\(index + 1). "
        }
        // Bullet (or fallback)
        let leading = leadingWhitespace(of: line)
        return leading + "- "
    }

    private static func leadingWhitespace(of line: String) -> String {
        var out = ""
        for ch in line {
            if ch == " " || ch == "\t" { out.append(ch) } else { break }
        }
        return out
    }
}
