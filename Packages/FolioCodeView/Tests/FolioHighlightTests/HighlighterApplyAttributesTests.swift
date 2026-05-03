import Testing
import Foundation
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
@testable import FolioHighlight

@Suite struct HighlighterApplyAttributesTests {
    private let monoFont: PlatformFont = .monospacedSystemFont(ofSize: 11, weight: .regular)

    @Test func applyInitialAttributesPaintsBaseColorAndFont() {
        let storage = NSTextStorage(string: "let x = 1;")
        let highlighter = FolioHighlighter(theme: .light)
        highlighter.applyInitialAttributes(
            to: storage,
            text: storage.string,
            language: .javascript,
            font: monoFont
        )

        let attrs0 = storage.attributes(at: 0, effectiveRange: nil)
        let font = attrs0[.font] as? PlatformFont
        #expect(font == monoFont)
        let color = attrs0[.foregroundColor] as? PlatformColor
        #expect(color != nil)
    }

    @Test func applyInitialAttributesPaintsKeywordColorForJavaScript() {
        let storage = NSTextStorage(string: "let x = 1;")
        let highlighter = FolioHighlighter(theme: .light)
        highlighter.applyInitialAttributes(
            to: storage,
            text: storage.string,
            language: .javascript,
            font: monoFont
        )

        let keywordColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
        #expect(keywordColor == HighlightTheme.light.keyword)
    }

    @Test func applyEditAttributesTouchesOnlyInvalidatedRange() {
        let initial = "let x = 1;\nlet y = 2;"
        let storage = NSTextStorage(string: initial)
        let highlighter = FolioHighlighter(theme: .light)
        highlighter.applyInitialAttributes(
            to: storage,
            text: initial,
            language: .javascript,
            font: monoFont
        )

        let sentinelRange = NSRange(location: 0, length: 1)
        let sentinelColor = PlatformColor(red: 1, green: 0, blue: 1, alpha: 1)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: sentinelColor, range: sentinelRange)
        storage.endEditing()

        let editRange = NSRange(location: 11, length: 10)
        let updated = "let x = 1;\nconst y = 2;"
        storage.replaceCharacters(in: editRange, with: "const y = 2;")
        let edit = highlighter.didEdit(
            replacedRange: editRange,
            replacement: "const y = 2;",
            in: updated
        )

        if edit.invalidatedRange.location > 0 {
            let preservedColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
            #expect(preservedColor == sentinelColor)
        }

        highlighter.applyEditAttributes(to: storage, edit: edit, font: monoFont)

        if edit.invalidatedRange.location > 0 {
            let preservedColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
            #expect(preservedColor == sentinelColor)
        }
    }

    @Test func applyEditAttributesEmptyRangeIsNoop() {
        let storage = NSTextStorage(string: "let x = 1;")
        let highlighter = FolioHighlighter(theme: .light)
        highlighter.applyInitialAttributes(
            to: storage,
            text: storage.string,
            language: .javascript,
            font: monoFont
        )
        let snapshot = storage.attributedSubstring(from: NSRange(location: 0, length: storage.length))
        let edit = FolioHighlighter.EditResult(
            invalidatedRange: NSRange(location: 0, length: 0),
            newRuns: []
        )
        highlighter.applyEditAttributes(to: storage, edit: edit, font: monoFont)
        let after = storage.attributedSubstring(from: NSRange(location: 0, length: storage.length))
        #expect(snapshot.isEqual(to: after))
    }

    @Test func textRoundtripsUnchanged() {
        let initial = "let x = \"héllo 🌟\";"
        let storage = NSTextStorage(string: initial)
        let highlighter = FolioHighlighter(theme: .light)
        highlighter.applyInitialAttributes(
            to: storage,
            text: initial,
            language: .javascript,
            font: monoFont
        )
        #expect(storage.string == initial)
    }

    @Test func plainLanguageStillPaintsBaseAttributes() {
        let storage = NSTextStorage(string: "anything goes")
        let highlighter = FolioHighlighter(theme: .light)
        highlighter.applyInitialAttributes(
            to: storage,
            text: storage.string,
            language: .plain,
            font: monoFont
        )
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
        #expect(font == monoFont)
        #expect(color == HighlightTheme.light.foreground)
    }
}
