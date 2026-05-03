import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum InsertNewline {

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
        guard let listAttr = storage.safeAttribute(.marginaliaListItem, at: probe) as? ListItemAttribute else {
            return nil
        }
        let lineRange = ns.paragraphRange(for: NSRange(location: probe, length: 0))

        if isEmptyListLine(in: storage, lineRange: lineRange) {
            let plainAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.bodyFont,
                .foregroundColor: theme.foregroundColor,
                .paragraphStyle: NSParagraphStyle(),
                .marginaliaBlock: BlockAttribute(tag: .paragraph)
            ]
            let replacement = NSAttributedString(string: "\n", attributes: plainAttrs)
            storage.beginEditing()
            storage.replaceCharacters(in: lineRange, with: replacement)
            storage.endEditing()
            return NSRange(location: lineRange.location, length: 0)
        }

        let nextOrderedIndex: Int? = listAttr.kind == .ordered ? (listAttr.orderedIndex ?? 0) + 1 : nil
        let nextChecked: Bool? = listAttr.kind == .task ? false : nil
        let nextItem = compiler.makeListItem(
            kind: listAttr.kind,
            level: listAttr.level,
            orderedIndex: nextOrderedIndex,
            isChecked: nextChecked,
            theme: theme
        )

        let insertLocation = lineRange.location + lineRange.length
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: insertLocation, length: 0), with: nextItem)
        storage.endEditing()
        let cursorAt = insertLocation + nextItem.length - 1
        return NSRange(location: max(insertLocation, cursorAt), length: 0)
    }

    /// True if `lineRange` contains only the marker run (FFFC, marker text,
    /// space, tab) plus a trailing newline — i.e., the user has not typed any
    /// body content for this list item.
    private static func isEmptyListLine(in storage: NSTextStorage, lineRange: NSRange) -> Bool {
        guard lineRange.length > 0,
              lineRange.location + lineRange.length <= storage.length,
              lineRange.location < storage.length else {
            return true
        }
        var bodyStart = lineRange.location
        var markerRange = NSRange(location: lineRange.location, length: 0)
        if let flag = storage.safeAttribute(.marginaliaListMarker, at: lineRange.location, longestEffectiveRange: &markerRange, in: lineRange) as? Bool, flag {
            bodyStart = markerRange.location + markerRange.length
        }
        let bodyEnd = lineRange.location + lineRange.length
        guard bodyEnd > bodyStart else { return true }
        let body = (storage.string as NSString).substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
        let trimmed = body.replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
    }
}
