import Foundation

/// The result of an editing operation: a new text value and the resulting selection.
///
/// `selection` is in UTF-16 code-unit offsets, matching `NSRange` and TextKit's
/// `NSTextStorage` conventions. Both fields refer to the *new* text in `text`.
public struct EditResult: Equatable {
    public var text: String
    public var selection: NSRange

    public init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }
}

/// Pure-Swift transforms over (text, selection) pairs, used by `Marginalia`'s
/// formatting toolbar and keyboard shortcuts. No UIKit / AppKit / SwiftUI.
public enum EditingOps {

    /// Wraps the selection with `prefix` and `suffix`, or inserts
    /// `prefix + placeholder + suffix` at the cursor when the selection is empty.
    ///
    /// - For a non-empty selection, the resulting selection covers the entire
    ///   wrapped span (prefix + content + suffix), letting the user see the
    ///   change and easily extend.
    /// - For an empty selection, the resulting selection covers the placeholder
    ///   text, so typing replaces the placeholder.
    public static func wrap(
        in text: String,
        selection: NSRange,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> EditResult {
        let ns = text as NSString
        let prefixLen = (prefix as NSString).length
        let suffixLen = (suffix as NSString).length

        if selection.length == 0 {
            let inserted = prefix + placeholder + suffix
            let newText = ns.replacingCharacters(in: selection, with: inserted)
            let placeholderRange = NSRange(
                location: selection.location + prefixLen,
                length: (placeholder as NSString).length
            )
            return EditResult(text: newText, selection: placeholderRange)
        }

        let selected = ns.substring(with: selection)
        let inserted = prefix + selected + suffix
        let newText = ns.replacingCharacters(in: selection, with: inserted)
        let newSelection = NSRange(
            location: selection.location,
            length: prefixLen + selection.length + suffixLen
        )
        return EditResult(text: newText, selection: newSelection)
    }

    /// Prefixes each line covered by the selection with `marker`.
    ///
    /// The selection is implicitly extended to full line boundaries so a partial
    /// mid-line selection still bullets/quotes the whole lines it touches —
    /// matching SimpleMDE / typical IDE behavior.
    ///
    /// - For a non-empty selection, the resulting selection covers the entire
    ///   prefixed block.
    /// - For an empty selection, the cursor is shifted right by `marker.length`
    ///   so the user remains in their original column.
    public static func prefixLines(
        in text: String,
        selection: NSRange,
        marker: String
    ) -> EditResult {
        let ns = text as NSString
        let lineRange = lineRangeExcludingTerminator(in: ns, covering: selection)
        let block = ns.substring(with: lineRange)
        let prefixed = block
            .components(separatedBy: "\n")
            .map { marker + $0 }
            .joined(separator: "\n")
        let newText = ns.replacingCharacters(in: lineRange, with: prefixed)
        let markerLen = (marker as NSString).length

        if selection.length == 0 {
            let newCursor = selection.location + markerLen
            return EditResult(text: newText, selection: NSRange(location: newCursor, length: 0))
        }
        return EditResult(
            text: newText,
            selection: NSRange(location: lineRange.location, length: (prefixed as NSString).length)
        )
    }

    /// Numbers each line covered by the selection (`1. `, `2. `, …).
    ///
    /// Same line-extension behavior as `prefixLines`.
    public static func numberedList(
        in text: String,
        selection: NSRange
    ) -> EditResult {
        let ns = text as NSString
        let lineRange = lineRangeExcludingTerminator(in: ns, covering: selection)
        let block = ns.substring(with: lineRange)
        let numbered = block
            .components(separatedBy: "\n")
            .enumerated()
            .map { idx, line in "\(idx + 1). \(line)" }
            .joined(separator: "\n")
        let newText = ns.replacingCharacters(in: lineRange, with: numbered)

        if selection.length == 0 {
            let firstMarkerLen = ("1. " as NSString).length
            let newCursor = selection.location + firstMarkerLen
            return EditResult(text: newText, selection: NSRange(location: newCursor, length: 0))
        }
        return EditResult(
            text: newText,
            selection: NSRange(location: lineRange.location, length: (numbered as NSString).length)
        )
    }

    /// Wraps the selection in a triple-backtick fenced code block, or inserts
    /// an empty fence at the cursor when the selection is empty.
    ///
    /// A leading newline is added when needed so the opening fence always
    /// starts at column 0 (otherwise `let x = ` ``` would not parse as a fence).
    /// Trailing newlines in the selected content are trimmed so the closing
    /// fence sits flush against the last line of code.
    public static func wrapCodeBlock(
        in text: String,
        selection: NSRange,
        placeholder: String = "code"
    ) -> EditResult {
        let ns = text as NSString
        let needsLeadingNewline = selection.location > 0
            && ns.character(at: selection.location - 1) != UInt16(0x0A)
        let leading = needsLeadingNewline ? "\n" : ""
        let leadingLen = (leading as NSString).length
        let openFence = "```\n"
        let openFenceLen = (openFence as NSString).length

        if selection.length == 0 {
            let inserted = "\(leading)\(openFence)\(placeholder)\n```\n"
            let newText = ns.replacingCharacters(in: selection, with: inserted)
            let placeholderRange = NSRange(
                location: selection.location + leadingLen + openFenceLen,
                length: (placeholder as NSString).length
            )
            return EditResult(text: newText, selection: placeholderRange)
        }

        var inner = ns.substring(with: selection)
        while inner.hasSuffix("\n") { inner.removeLast() }
        let inserted = "\(leading)\(openFence)\(inner)\n```\n"
        let newText = ns.replacingCharacters(in: selection, with: inserted)
        return EditResult(
            text: newText,
            selection: NSRange(location: selection.location, length: (inserted as NSString).length)
        )
    }

    private static func lineRangeExcludingTerminator(
        in ns: NSString,
        covering range: NSRange
    ) -> NSRange {
        var lr = ns.lineRange(for: range)
        if lr.length > 0 {
            let lastIdx = lr.location + lr.length - 1
            if ns.character(at: lastIdx) == UInt16(0x0A) {
                lr.length -= 1
            }
        }
        return lr
    }
}
