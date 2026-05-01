import Foundation
import CoreText
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension NSAttributedString.Key {
    /// Raw-string version of `NSAttributedString.Key.glyphInfo` — that
    /// Swift-extension symbol isn't reliably exposed on every SDK
    /// (notably some macOS ones), but the underlying attribute name is the
    /// stable string `"NSGlyphInfo"` (what AppKit's `NSGlyphInfoAttributeName`
    /// resolves to). The TextKit layout manager honors a `CTGlyphInfo`
    /// value under this key for character-to-glyph substitution.
    public static let glyphInfoCompat = NSAttributedString.Key("NSGlyphInfo")
}

/// Maps `-` / `*` / `+` list markers in the editor to a per-level bullet
/// glyph (• → ◦ → ▪ → ▫ → •). The actual character substitution at render
/// time is done with `NSAttributedString.Key.glyphInfo` + a `CTGlyphInfo`
/// pointing at the bullet's glyph in the body font — so the source text
/// keeps its ASCII marker but the editor draws a bullet.
public enum BulletAttachment {

    /// Glyph for the given `level` (0 = top-level, 1 = first-nested, …),
    /// cycling every 4 levels so deeply-nested items still read.
    public static func glyph(forLevel level: Int) -> String {
        switch ((level % 4) + 4) % 4 {
        case 0: return "•"
        case 1: return "◦"
        case 2: return "▪"
        case 3: return "▫"
        default: return "•"
        }
    }

    /// Computes the nesting level from a list line's leading-whitespace
    /// prefix. Two spaces (or one tab) per level — the convention
    /// Markdown editors use for nested bullets.
    public static func level(forLeading leading: String) -> Int {
        var spaces = 0
        for ch in leading {
            if ch == "\t" { spaces += 2 }
            else if ch == " " { spaces += 1 }
            else { break }
        }
        return spaces / 2
    }
}
