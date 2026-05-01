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

    /// What kind of list a line currently is — used by the toolbar's
    /// list-button action to decide between "indent" (when the user clicks
    /// the same kind they're already in) and "switch type" (when they click
    /// a different kind).
    public enum ListKind: Sendable {
        case bullet
        case numbered
        case task
    }

    /// Drives the list-button toolbar action with the "smart" semantics:
    /// - cursor on a list line of the *same* `kind` → indent that line
    /// - cursor on a list line of a *different* kind → swap the marker
    /// - cursor on a non-list line → add the marker (prefix the line)
    public static func applyListMarker(
        in text: String,
        selection: NSRange,
        kind: ListKind
    ) -> EditResult? {
        let ns = text as NSString
        let lineRange = lineRangeExcludingTerminator(in: ns, covering: selection)
        let firstLine = ns.substring(with: lineRange).components(separatedBy: "\n").first ?? ""

        if let current = listKind(of: firstLine) {
            if current == kind {
                return indentListLines(in: text, selection: selection)
            } else {
                return switchListMarker(in: text, selection: selection, to: kind)
            }
        }
        switch kind {
        case .bullet:
            return prefixLines(in: text, selection: selection, marker: "- ")
        case .task:
            return prefixLines(in: text, selection: selection, marker: "- [ ] ")
        case .numbered:
            return numberedList(in: text, selection: selection)
        }
    }

    /// Replaces the leading list marker on each line of the selection with
    /// a `kind`-typed one — bullet → `- `, task → `- [ ] `, numbered → `1. `,
    /// `2. `, etc. Returns `nil` if no line had a marker to replace.
    public static func switchListMarker(
        in text: String,
        selection: NSRange,
        to kind: ListKind
    ) -> EditResult? {
        let ns = text as NSString
        let lineRange = lineRangeExcludingTerminator(in: ns, covering: selection)
        let block = ns.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")

        var changed = false
        var counter = 1
        let updated = lines.map { line -> String in
            guard let stripped = stripListMarker(from: line) else { return line }
            changed = true
            let marker: String
            switch kind {
            case .bullet: marker = "- "
            case .task: marker = "- [ ] "
            case .numbered:
                marker = "\(counter). "
                counter += 1
            }
            return stripped.leading + marker + stripped.rest
        }.joined(separator: "\n")

        guard changed else { return nil }

        let newText = ns.replacingCharacters(in: lineRange, with: updated)
        let firstOld = lines.first ?? ""
        let firstNew = updated.components(separatedBy: "\n").first ?? ""
        let firstLineDelta = (firstNew as NSString).length - (firstOld as NSString).length

        if selection.length == 0 {
            let newCursor = max(lineRange.location, selection.location + firstLineDelta)
            return EditResult(text: newText, selection: NSRange(location: newCursor, length: 0))
        }
        let totalDelta = (updated as NSString).length - (block as NSString).length
        return EditResult(
            text: newText,
            selection: NSRange(
                location: selection.location,
                length: max(0, selection.length + totalDelta)
            )
        )
    }

    private static func listKind(of line: String) -> ListKind? {
        if line.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil {
            return .task
        }
        if line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) != nil {
            return .bullet
        }
        if line.range(of: #"^\s*\d+\.\s+"#, options: .regularExpression) != nil {
            return .numbered
        }
        return nil
    }

    private static func stripListMarker(from line: String) -> (leading: String, rest: String)? {
        let pattern = #"^(\s*)([-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+\.\s+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: ns.length)
        ) else { return nil }
        let leading = ns.substring(with: match.range(at: 1))
        let rest = ns.substring(from: match.range.upperBound)
        return (leading, rest)
    }

    /// Indents the list item(s) covered by the selection by `indent` (default
    /// two spaces). A "list line" is a bullet, numbered, task, or blockquote
    /// line as detected by `ListMarker`. Lines that aren't list lines are
    /// left unchanged. Returns the input unchanged if no list line is touched
    /// — letting the caller fall through to the system's Tab behavior.
    public static func indentListLines(
        in text: String,
        selection: NSRange,
        indent: String = "  "
    ) -> EditResult? {
        let ns = text as NSString
        let lineRange = lineRangeExcludingTerminator(in: ns, covering: selection)
        let block = ns.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")

        var changed = false
        let updated = lines.map { line -> String in
            if isListLine(line) {
                changed = true
                return indent + line
            }
            return line
        }.joined(separator: "\n")

        guard changed else { return nil }

        let newText = ns.replacingCharacters(in: lineRange, with: updated)
        let indentLen = (indent as NSString).length
        let firstLineChanged = isListLine(lines.first ?? "")
        let leadingShift = firstLineChanged ? indentLen : 0
        let totalAdded = (updated as NSString).length - (block as NSString).length

        if selection.length == 0 {
            return EditResult(
                text: newText,
                selection: NSRange(location: selection.location + leadingShift, length: 0)
            )
        }
        return EditResult(
            text: newText,
            selection: NSRange(
                location: selection.location + leadingShift,
                length: max(0, selection.length + totalAdded - leadingShift)
            )
        )
    }

    /// Outdents the list item(s) covered by the selection — strips a leading
    /// `indent` (2 spaces) or a single leading tab from each list line.
    /// Returns the input unchanged if no line had a removable indent.
    public static func outdentListLines(
        in text: String,
        selection: NSRange,
        indent: String = "  "
    ) -> EditResult? {
        let ns = text as NSString
        let lineRange = lineRangeExcludingTerminator(in: ns, covering: selection)
        let block = ns.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        let indentLen = (indent as NSString).length

        var changed = false
        let updated = lines.map { line -> String in
            if line.hasPrefix(indent), isListLine(String(line.dropFirst(indent.count))) {
                changed = true
                return String(line.dropFirst(indent.count))
            }
            if line.hasPrefix("\t"), isListLine(String(line.dropFirst())) {
                changed = true
                return String(line.dropFirst())
            }
            return line
        }.joined(separator: "\n")

        guard changed else { return nil }

        let newText = ns.replacingCharacters(in: lineRange, with: updated)
        let firstLine = lines.first ?? ""
        let firstLineLeadingRemoved: Int = {
            if firstLine.hasPrefix(indent), isListLine(String(firstLine.dropFirst(indent.count))) {
                return indentLen
            }
            if firstLine.hasPrefix("\t"), isListLine(String(firstLine.dropFirst())) {
                return 1
            }
            return 0
        }()
        let totalRemoved = (block as NSString).length - (updated as NSString).length

        if selection.length == 0 {
            let newCursor = max(lineRange.location, selection.location - firstLineLeadingRemoved)
            return EditResult(text: newText, selection: NSRange(location: newCursor, length: 0))
        }
        return EditResult(
            text: newText,
            selection: NSRange(
                location: max(lineRange.location, selection.location - firstLineLeadingRemoved),
                length: max(0, selection.length - totalRemoved + firstLineLeadingRemoved)
            )
        )
    }

    private static func isListLine(_ line: String) -> Bool {
        line.range(of: #"^\s*([-*+]|\d+\.)\s+"#, options: .regularExpression) != nil
    }

    /// Inserts a thematic break (`---`) at the cursor on its own line.
    ///
    /// Adds a leading newline if the cursor isn't already at the start of a
    /// line, and a trailing blank line so the rule is followed by a fresh
    /// paragraph. The cursor lands after the trailing blank line so the
    /// user can keep typing.
    public static func insertHorizontalRule(
        in text: String,
        selection: NSRange
    ) -> EditResult {
        let ns = text as NSString
        let location = max(0, min(selection.location, ns.length))

        let needsLeadingNewline = location > 0
            && ns.character(at: location - 1) != UInt16(0x0A)
        let leading = needsLeadingNewline ? "\n" : ""
        let inserted = "\(leading)---\n\n"

        let replaceRange = NSRange(
            location: location,
            length: max(0, min(selection.length, ns.length - location))
        )
        let newText = ns.replacingCharacters(in: replaceRange, with: inserted)
        let newCursor = location + (inserted as NSString).length
        return EditResult(text: newText, selection: NSRange(location: newCursor, length: 0))
    }

    private static func lineRangeExcludingTerminator(
        in ns: NSString,
        covering range: NSRange
    ) -> NSRange {
        // Clamp the input range first — `NSString.lineRange(for:)` throws
        // `NSRangeException` on an out-of-bounds range, which used to bring
        // the whole app down when a stale selection was fed in (e.g. a
        // Shift-Tab outdent computed against text shorter than what the
        // cursor expected). Clamping turns that into a no-op at the end of
        // the string.
        var lr = ns.lineRange(for: range.clamped(to: ns.length))
        if lr.length > 0 {
            let lastIdx = lr.location + lr.length - 1
            if ns.character(at: lastIdx) == UInt16(0x0A) {
                lr.length -= 1
            }
        }
        return lr
    }
}
