import Testing
import Foundation
import MarginaliaSyntax
@testable import MarginaliaView

@Suite(.serialized) struct EditorControllerTests {

    @Test func initialTextSetsStorage() throws {
        let c = try EditorController(initialText: "hello")
        #expect(c.textStorage.string == "hello")
        #expect(c.text == "hello")
    }

    @Test func setTextReplacesContent() throws {
        let c = try EditorController(initialText: "hello")
        c.setText("# heading")
        #expect(c.text == "# heading")
    }

    @Test func initialRefreshComputesBlockRegions() throws {
        let c = try EditorController(initialText: "# heading\nbody\n")
        c.refreshNow()
        let kinds = c.blockRegions.map { $0.kind }
        #expect(kinds.contains(where: { if case .heading = $0 { return true } else { return false } }))
        #expect(kinds.contains(.paragraph))
    }

    @Test func highlightAttributesApplied() throws {
        let c = try EditorController(initialText: "**bold**")
        c.refreshNow()
        var effective: NSRange = NSRange(location: 0, length: 0)
        let attrs = c.textStorage.attributes(at: 2, effectiveRange: &effective)
        #expect(attrs[.font] != nil)
    }

    @Test func applyEditUpdatesStorage() throws {
        let c = try EditorController(initialText: "Hello\n")
        c.applyEdit(replacing: NSRange(location: 0, length: 0), with: "# ")
        c.refreshNow()
        #expect(c.text == "# Hello\n")
    }

    @Test func selectionTriggersHiddenRecompute() throws {
        let c = try EditorController(initialText: "**a**\n**b**")
        c.refreshNow()
        c.selection = NSRange(location: 2, length: 0)
        let hidden0 = c.hiddenRanges
        c.selection = NSRange(location: 8, length: 0)
        let hidden1 = c.hiddenRanges
        #expect(hidden0 != hidden1, "hidden ranges should change with cursor")
    }

    @Test func textKitStackIsConfigured() throws {
        let c = try EditorController()
        #expect(c.contentStorage.textStorage == c.textStorage)
        #expect(c.contentStorage.textLayoutManagers.contains(c.layoutManager))
        #expect(c.layoutManager.textContainer == c.textContainer)
    }

    @Test func dialectSwitchTriggersRefresh() throws {
        let c = try EditorController(initialText: "//italic//")
        c.dialect = .remarkup
        c.refreshNow()
        #expect(c.dialect == .remarkup)
    }

    @Test func emptyTextProducesEmptyState() throws {
        let c = try EditorController(initialText: "")
        c.refreshNow()
        #expect(c.blockRegions == [])
        #expect(c.markupRanges == [])
        #expect(c.hiddenRanges == [])
    }

    // MARK: - applyEdit(EditResult)

    @Test func applyEditUpdatesTextAndSelection() throws {
        let c = try EditorController(initialText: "hello")
        let result = EditResult(text: "hello world", selection: NSRange(location: 6, length: 5))
        c.applyEdit(result)
        #expect(c.text == "hello world")
        #expect(c.selection == NSRange(location: 6, length: 5))
    }

    @Test func applyEditClampsSelectionPastNewTextEnd() throws {
        let c = try EditorController(initialText: "")
        let result = EditResult(
            text: "1. ",
            selection: NSRange(location: 159, length: 28)
        )
        c.applyEdit(result)
        #expect(c.text == "1. ")
        #expect(c.selection.location == 3)
        #expect(c.selection.length == 0)
    }

    @Test func clampedRangeShrinksOutOfBoundsRange() throws {
        let c = try EditorController(initialText: "hello")
        let clamped = c.clampedRange(NSRange(location: 159, length: 28))
        #expect(clamped == NSRange(location: 5, length: 0))
    }
}
