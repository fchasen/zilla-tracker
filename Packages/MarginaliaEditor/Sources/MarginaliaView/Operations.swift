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

    // MARK: - helpers

    private static func clampedRange(_ range: NSRange, in length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let remaining = max(0, length - location)
        return NSRange(location: location, length: max(0, min(range.length, remaining)))
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
