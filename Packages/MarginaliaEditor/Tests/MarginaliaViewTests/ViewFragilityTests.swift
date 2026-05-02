import Testing
import Foundation
import MarginaliaSyntax
@testable import MarginaliaView

@Suite(.serialized) struct EditorControllerFragilityTests {

    @Test func textRoundTripsThroughController() throws {
        let source = "# Heading\n\nplain paragraph"
        let c = try EditorController(initialText: source)
        c.refreshNow()
        #expect(c.text == source)
    }

    @Test func rapidSequentialApplyEditsConvergeWithFromScratchParse() throws {
        let c = try EditorController(initialText: "")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "hello")
        c.applyEdit(replacing: NSRange(location: 5, length: 0), with: " world")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ")
        c.refreshNow()

        let final = c.text
        let fresh = try MarkdownParser(grammar: .block)
        fresh.parse(final)
        let root = try #require(fresh.rootNode)

        let kindsFresh = BlockClassifier.classify(rootNode: root, mapping: fresh.mapping).map { $0.kind }
        let kindsLive = c.blockRegions.map { $0.kind }
        #expect(kindsLive == kindsFresh)
    }

    @Test func highlightAttributesAfterMultilineEditCoverNewParagraphs() throws {
        let c = try EditorController(initialText: "")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# heading\n\n")
        c.applyEdit(replacing: NSRange(location: 11, length: 0), with: "- item\n")
        c.refreshNow()
        let kinds = c.blockRegions.map { $0.kind }
        let hasHeading = kinds.contains(where: { if case .heading = $0 { return true } else { return false } })
        #expect(hasHeading)
        #expect(kinds.contains(.unorderedList))
    }

    @Test func setTextAcrossEmojiBoundaryDoesNotCrash() throws {
        let c = try EditorController(initialText: "🚀 hello 🚀")
        c.refreshNow()
        c.setText("🚀")
        c.refreshNow()
        #expect(c.text == "🚀")
    }

    @Test func applyEditResultClampsStaleSelectionWithoutCrash() throws {
        let c = try EditorController(initialText: "")
        c.selection = NSRange(location: 999, length: 5)
        c.applyEdit(EditResult(text: "short", selection: NSRange(location: 999, length: 5)))
        #expect(c.text == "short")
        #expect(c.selection.location == 5)
        #expect(c.selection.length == 0)
    }

    @Test func bareControllerInit() throws {
        let c = try EditorController(initialText: "")
        #expect(c.text == "")
    }

    @Test func controllerInitWithMarkdown() throws {
        let c = try EditorController(initialText: "# H\n")
        #expect(c.text == "# H\n")
    }
}
