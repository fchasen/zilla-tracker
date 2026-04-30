import Foundation

/// Computes the markup ranges that should be visually hidden ("focus mode").
///
/// The MVP rule: any markup range that does *not* live on the cursor's current
/// line is hidden — the editor will paint those characters with a clear
/// foreground so the prose reads cleanly. As the cursor moves between lines
/// the hidden set shifts to keep the active line legible.
public enum HiddenRangeComputer {
    /// - Parameters:
    ///   - markupRanges: NSRanges of characters classified as markup
    ///     (tagged `punctuation.special` / `punctuation.delimiter` by the
    ///     highlighter).
    ///   - cursorRange: the current selection / insertion point. A non-empty
    ///     selection counts every line it touches as "active".
    ///   - text: the current source text (used for line-range arithmetic).
    /// - Returns: the subset of `markupRanges` that should be hidden.
    public static func hiddenRanges(
        markupRanges: [NSRange],
        cursorRange: NSRange,
        in text: String
    ) -> [NSRange] {
        guard !markupRanges.isEmpty else { return [] }
        let ns = text as NSString
        let activeLineRange = ns.lineRange(for: cursorRange)

        return markupRanges.filter { mr in
            let mrLine = ns.lineRange(for: mr)
            return !rangesOverlap(mrLine, activeLineRange)
        }
    }

    private static func rangesOverlap(_ a: NSRange, _ b: NSRange) -> Bool {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        return a.location < bEnd && b.location < aEnd
    }
}
