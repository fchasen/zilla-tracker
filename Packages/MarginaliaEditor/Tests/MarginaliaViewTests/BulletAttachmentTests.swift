#if canImport(AppKit) && os(macOS)
import Testing
import AppKit
import MarginaliaSyntax
import MarginaliaRendering
@testable import MarginaliaView

@Suite(.serialized) struct BulletAttachmentTests {

    // MARK: - glyph + level mapping

    @Test func glyphCyclesPerLevel() {
        #expect(BulletAttachment.glyph(forLevel: 0) == "•")
        #expect(BulletAttachment.glyph(forLevel: 1) == "◦")
        #expect(BulletAttachment.glyph(forLevel: 2) == "▪")
        #expect(BulletAttachment.glyph(forLevel: 3) == "▫")
        #expect(BulletAttachment.glyph(forLevel: 4) == "•")
    }

    @Test func levelFromLeading() {
        #expect(BulletAttachment.level(forLeading: "") == 0)
        #expect(BulletAttachment.level(forLeading: "  ") == 1)
        #expect(BulletAttachment.level(forLeading: "    ") == 2)
        #expect(BulletAttachment.level(forLeading: "\t") == 1)
        #expect(BulletAttachment.level(forLeading: "\t\t") == 2)
    }

    // MARK: - integration with the controller

    @Test func topLevelBulletGetsGlyphSubstitution() throws {
        let c = try EditorController(initialText: "- foo")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        #expect(attrs[.glyphInfoCompat] != nil,
                "Expected glyphInfo substitution on top-level dash.")
    }

    @Test func nestedBulletGetsDifferentGlyph() throws {
        let c = try EditorController(initialText: "- top\n  - nested\n")
        c.refreshNow()
        var topRange = NSRange()
        let topAttrs = c.textStorage.attributes(at: 0, effectiveRange: &topRange)
        var nestRange = NSRange()
        let nestAttrs = c.textStorage.attributes(at: 8, effectiveRange: &nestRange)
        let topInfo = topAttrs[.glyphInfo]
        let nestInfo = nestAttrs[.glyphInfo]
        #expect(topInfo != nil)
        #expect(nestInfo != nil)
        if let topGI = topInfo, let nestGI = nestInfo {
            #expect(!(topGI as AnyObject === nestGI as AnyObject))
        }
    }

    @Test func bulletNotAppliedToHorizontalRule() throws {
        let c = try EditorController(initialText: "---\n")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        #expect(attrs[.glyphInfoCompat] == nil)
    }

    @Test func bulletNotAppliedToNumberedListMarker() throws {
        let c = try EditorController(initialText: "1. one\n")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        #expect(attrs[.glyphInfoCompat] == nil)
    }

    @Test func taskMarkerDashGetsBulletGlyph() throws {
        let c = try EditorController(initialText: "- [ ] task")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        #expect(attrs[.glyphInfoCompat] != nil)
    }
}
#endif
