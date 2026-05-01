#if canImport(AppKit) && os(macOS)
import XCTest
import AppKit
import MarginaliaSyntax
import MarginaliaRendering
@testable import MarginaliaView

final class BulletAttachmentTests: XCTestCase {

    // MARK: - glyph + level mapping

    func testGlyphCyclesPerLevel() {
        XCTAssertEqual(BulletAttachment.glyph(forLevel: 0), "•")
        XCTAssertEqual(BulletAttachment.glyph(forLevel: 1), "◦")
        XCTAssertEqual(BulletAttachment.glyph(forLevel: 2), "▪")
        XCTAssertEqual(BulletAttachment.glyph(forLevel: 3), "▫")
        // Cycles back at 4
        XCTAssertEqual(BulletAttachment.glyph(forLevel: 4), "•")
    }

    func testLevelFromLeading() {
        XCTAssertEqual(BulletAttachment.level(forLeading: ""), 0)
        XCTAssertEqual(BulletAttachment.level(forLeading: "  "), 1)
        XCTAssertEqual(BulletAttachment.level(forLeading: "    "), 2)
        XCTAssertEqual(BulletAttachment.level(forLeading: "\t"), 1)
        XCTAssertEqual(BulletAttachment.level(forLeading: "\t\t"), 2)
    }

    // MARK: - integration with the controller

    func testTopLevelBulletGetsGlyphSubstitution() throws {
        let c = try EditorController(initialText: "- foo")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        XCTAssertNotNil(attrs[.glyphInfoCompat],
                        "Expected glyphInfo substitution on top-level dash.")
    }

    func testNestedBulletGetsDifferentGlyph() throws {
        let c = try EditorController(initialText: "- top\n  - nested\n")
        c.refreshNow()
        // Top-level dash at 0
        var topRange = NSRange()
        let topAttrs = c.textStorage.attributes(at: 0, effectiveRange: &topRange)
        // Nested dash at 8 (after "- top\n  ")
        var nestRange = NSRange()
        let nestAttrs = c.textStorage.attributes(at: 8, effectiveRange: &nestRange)
        let topInfo = topAttrs[.glyphInfo]
        let nestInfo = nestAttrs[.glyphInfo]
        XCTAssertNotNil(topInfo)
        XCTAssertNotNil(nestInfo)
        // The two glyph-info instances should be different identities (different
        // glyph for each level).
        if let topGI = topInfo, let nestGI = nestInfo {
            XCTAssertFalse(topGI as AnyObject === nestGI as AnyObject)
        }
    }

    func testBulletNotAppliedToHorizontalRule() throws {
        // `---` is a horizontal rule, not a list. The first dash must not
        // get a bullet glyph.
        let c = try EditorController(initialText: "---\n")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        XCTAssertNil(attrs[.glyphInfoCompat])
    }

    func testBulletNotAppliedToNumberedListMarker() throws {
        let c = try EditorController(initialText: "1. one\n")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        XCTAssertNil(attrs[.glyphInfoCompat])
    }

    func testTaskMarkerDashGetsBulletGlyph() throws {
        let c = try EditorController(initialText: "- [ ] task")
        c.refreshNow()
        var range = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 0, effectiveRange: &range)
        XCTAssertNotNil(attrs[.glyphInfoCompat])
    }
}
#endif
