import Foundation
import Testing
@testable import MarkdownEditorKit

@Suite("Document change")
struct DocumentChangeTests {
    @Test func rangeAfterAnEditShiftsByTheChangeInLength() {
        let range = NSRange(location: 10, length: 2)
        #expect(range.shifted(byEdit: NSRange(location: 2, length: 3), changeInLength: 3) == NSRange(location: 13, length: 2))
        #expect(range.shifted(byEdit: NSRange(location: 2, length: 0), changeInLength: -4) == NSRange(location: 6, length: 2))
    }

    @Test func rangeBeforeAnEditKeepsItsPosition() {
        let range = NSRange(location: 0, length: 2)
        #expect(range.shifted(byEdit: NSRange(location: 5, length: 1), changeInLength: 1) == range)
    }

    @Test func rangeInsideReplacedTextCollapsesOntoTheEdit() {
        let range = NSRange(location: 5, length: 2)
        #expect(range.shifted(byEdit: NSRange(location: 3, length: 0), changeInLength: -5) == NSRange(location: 3, length: 0))
        let overlapping = NSRange(location: 4, length: 4)
        #expect(overlapping.shifted(byEdit: NSRange(location: 6, length: 1), changeInLength: -3) == NSRange(location: 4, length: 3))
    }

    @Test func mergeCoversBothEdits() {
        let earlier = NSRange(location: 20, length: 1)
        #expect(earlier.merged(withEdit: NSRange(location: 2, length: 3), changeInLength: 3) == NSRange(location: 2, length: 22))
    }

    @Test @MainActor func coalescedChangeCoversEditsMadeOutOfOrder() throws {
        let controller = MarkdownEditorController(markdown: "0123456789abcdefghij0123456789")
        var changes: [DocumentChange] = []
        controller.addOnDocumentChange { changes.append($0) }
        controller.textStorage.replaceCharacters(in: NSRange(location: 20, length: 0), with: "X")
        controller.textStorage.replaceCharacters(in: NSRange(location: 2, length: 0), with: "YYY")
        controller.flushDocumentChanges()
        let change = try #require(changes.last)
        #expect(change.changeInLength == 4)
        #expect(NSLocationInRange(2, change.editedRange))
        #expect(NSLocationInRange(23, change.editedRange))
    }
}
