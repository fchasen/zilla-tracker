import XCTest
import Foundation
import MarginaliaSyntax
@testable import MarginaliaView

final class EditorControllerFragilityTests: XCTestCase {

    func testTextRoundTripsThroughController() throws {
        let source = "# Heading\n\nplain paragraph"
        let c = try EditorController(initialText: source)
        c.refreshNow()
        XCTAssertEqual(c.text, source)
    }

    func testRapidSequentialApplyEditsConvergeWithFromScratchParse() throws {
        let c = try EditorController(initialText: "")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "hello")
        c.applyEdit(replacing: NSRange(location: 5, length: 0), with: " world")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ")
        c.refreshNow()

        let final = c.text
        let fresh = try MarkdownParser(grammar: .block)
        fresh.parse(final)

        let kindsFresh = BlockClassifier
            .classify(rootNode: fresh.rootNode!, mapping: fresh.mapping)
            .map { $0.kind }
        let kindsLive = c.blockRegions.map { $0.kind }
        XCTAssertEqual(kindsLive, kindsFresh)
    }

    func testHighlightAttributesAfterMultilineEditCoverNewParagraphs() throws {
        let c = try EditorController(initialText: "")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# heading\n\n")
        c.applyEdit(replacing: NSRange(location: 11, length: 0), with: "- item\n")
        c.refreshNow()
        let kinds = c.blockRegions.map { $0.kind }
        let hasHeading = kinds.contains(where: { if case .heading = $0 { return true } else { return false } })
        XCTAssertTrue(hasHeading)
        XCTAssertTrue(kinds.contains(.unorderedList))
    }

    func testSetTextAcrossEmojiBoundaryDoesNotCrash() throws {
        let c = try EditorController(initialText: "🚀 hello 🚀")
        c.refreshNow()
        c.setText("🚀")
        c.refreshNow()
        XCTAssertEqual(c.text, "🚀")
    }

    func testApplyEditResultClampsStaleSelectionWithoutCrash() throws {
        let c = try EditorController(initialText: "")
        c.selection = NSRange(location: 999, length: 5)
        c.applyEdit(EditResult(text: "short", selection: NSRange(location: 999, length: 5)))
        XCTAssertEqual(c.text, "short")
        XCTAssertEqual(c.selection.location, 5)
        XCTAssertEqual(c.selection.length, 0)
    }

    func testBareControllerInit() throws {
        let c = try EditorController(initialText: "")
        XCTAssertEqual(c.text, "")
    }

    func testControllerInitWithMarkdown() throws {
        let c = try EditorController(initialText: "# H\n")
        XCTAssertEqual(c.text, "# H\n")
    }
}
