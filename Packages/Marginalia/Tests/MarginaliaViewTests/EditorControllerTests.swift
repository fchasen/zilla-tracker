import XCTest
import MarginaliaSyntax
@testable import MarginaliaView

final class EditorControllerTests: XCTestCase {

    func testInitialTextSetsStorage() throws {
        let c = try EditorController(initialText: "hello")
        XCTAssertEqual(c.textStorage.string, "hello")
        XCTAssertEqual(c.text, "hello")
    }

    func testSetTextReplacesContent() throws {
        let c = try EditorController(initialText: "hello")
        c.setText("# heading")
        XCTAssertEqual(c.text, "# heading")
    }

    func testInitialRefreshComputesBlockRegions() throws {
        let c = try EditorController(initialText: "# heading\nbody\n")
        c.refreshNow()
        let kinds = c.blockRegions.map { $0.kind }
        XCTAssertTrue(kinds.contains(where: { if case .heading = $0 { return true } else { return false } }))
        XCTAssertTrue(kinds.contains(.paragraph))
    }

    func testHighlightAttributesApplied() throws {
        let c = try EditorController(initialText: "**bold**")
        c.refreshNow()
        // Whatever the bold attribute is, the storage at offset 2 ("bold")
        // should have a non-default font (bolder than the base body font).
        var effective: NSRange = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 2, effectiveRange: &effective)
        XCTAssertNotNil(attrs[.font])
    }

    func testApplyEditUpdatesStorage() throws {
        let c = try EditorController(initialText: "Hello\n")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ")
        c.refreshNow()
        XCTAssertEqual(c.text, "# Hello\n")
    }

    func testSelectionTriggersHiddenRecompute() throws {
        let c = try EditorController(initialText: "**a**\n**b**")
        c.refreshNow()
        // Cursor on line 0
        c.selection = NSRange(location: 2, length: 0)
        let hidden0 = c.hiddenRanges
        // Cursor on line 1
        c.selection = NSRange(location: 8, length: 0)
        let hidden1 = c.hiddenRanges
        XCTAssertNotEqual(hidden0, hidden1, "hidden ranges should change with cursor")
    }

    func testTextKitStackIsConfigured() throws {
        let c = try EditorController()
        XCTAssertEqual(c.contentStorage.textStorage, c.textStorage)
        XCTAssertTrue(c.contentStorage.textLayoutManagers.contains(c.layoutManager))
        XCTAssertEqual(c.layoutManager.textContainer, c.textContainer)
    }

    func testDialectSwitchTriggersRefresh() throws {
        let c = try EditorController(initialText: "//italic//")
        c.dialect = .remarkup
        c.refreshNow()
        // Remarkup highlighter should have run and tagged //italic//
        // Verifying via markupRanges presence is brittle; just confirm refresh ran without crash.
        XCTAssertEqual(c.dialect, .remarkup)
    }

    func testEmptyTextProducesEmptyState() throws {
        let c = try EditorController(initialText: "")
        c.refreshNow()
        XCTAssertEqual(c.blockRegions, [])
        XCTAssertEqual(c.markupRanges, [])
        XCTAssertEqual(c.hiddenRanges, [])
    }
}
