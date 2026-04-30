import Foundation

/// Smart Return key handling for list-like contexts (bullet, numbered, task,
/// blockquote). Returns a transformed `(text, selection)` pair, or `nil` if
/// the cursor is not on a list/quote line — in which case the caller should
/// fall through to the system's default Return behavior.
///
/// Semantics, matching SimpleMDE / GitHub-flavored editors:
/// - Cursor on a non-empty list item → insert `\n` + the same marker on the next line
/// - Cursor on an empty list item (only the marker, no content) → terminate the
///   list by removing the empty marker line
/// - Numbered lists increment (`1. ` → `2. `, `10. ` → `11. `)
/// - Task list items always continue with `[ ]` (a fresh checkbox), even if
///   the previous item was checked
/// - Indentation (spaces or tabs) is preserved on continuation
public enum ListContinuation {
    public static func handleReturn(in text: String, cursor: Int) -> EditResult? {
        let ns = text as NSString
        guard cursor >= 0, cursor <= ns.length else { return nil }

        var lineStart = cursor
        while lineStart > 0 && ns.character(at: lineStart - 1) != UInt16(0x0A) {
            lineStart -= 1
        }
        let lineToCursor = ns.substring(with: NSRange(location: lineStart, length: cursor - lineStart))

        guard let marker = ListMarker.detect(in: lineToCursor) else { return nil }

        let content = lineToCursor.dropFirst(marker.literal.count)
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            let removalRange = NSRange(location: lineStart, length: cursor - lineStart)
            let newText = ns.replacingCharacters(in: removalRange, with: "")
            return EditResult(text: newText, selection: NSRange(location: lineStart, length: 0))
        }

        let inserted = "\n" + marker.next
        let newText = ns.replacingCharacters(in: NSRange(location: cursor, length: 0), with: inserted)
        let newCursor = cursor + (inserted as NSString).length
        return EditResult(text: newText, selection: NSRange(location: newCursor, length: 0))
    }
}

struct ListMarker: Equatable {
    let literal: String
    let next: String

    static func detect(in line: String) -> ListMarker? {
        if let m = matchTaskList(line) { return m }
        if let m = matchBullet(line) { return m }
        if let m = matchNumbered(line) { return m }
        if let m = matchBlockquote(line) { return m }
        return nil
    }

    private static func matchTaskList(_ line: String) -> ListMarker? {
        guard let r = line.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) else { return nil }
        let literal = String(line[r])
        var next = literal
        if let bracket = next.range(of: #"\[[ xX]\]"#, options: .regularExpression) {
            next.replaceSubrange(bracket, with: "[ ]")
        }
        return ListMarker(literal: literal, next: next)
    }

    private static func matchBullet(_ line: String) -> ListMarker? {
        guard let r = line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) else { return nil }
        let literal = String(line[r])
        return ListMarker(literal: literal, next: literal)
    }

    private static func matchNumbered(_ line: String) -> ListMarker? {
        let pattern = #"^(\s*)(\d+)\.(\s+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let m = regex.firstMatch(in: line, range: range) else { return nil }
        let literal = nsLine.substring(with: m.range)
        let leading = nsLine.substring(with: m.range(at: 1))
        let numberStr = nsLine.substring(with: m.range(at: 2))
        let spaces = nsLine.substring(with: m.range(at: 3))
        let n = Int(numberStr) ?? 1
        let next = "\(leading)\(n + 1).\(spaces)"
        return ListMarker(literal: literal, next: next)
    }

    private static func matchBlockquote(_ line: String) -> ListMarker? {
        guard let r = line.range(of: #"^\s*>\s+"#, options: .regularExpression) else { return nil }
        let literal = String(line[r])
        return ListMarker(literal: literal, next: literal)
    }
}
