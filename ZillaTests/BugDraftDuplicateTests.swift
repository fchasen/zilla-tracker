import Foundation
import Testing
@testable import Zilla

@MainActor
struct BugDraftDuplicateTests {
    @Test func copiesEveryEditableField() {
        let draft = BugDraft(product: "Firefox", componentName: "General", blocks: [1, 2])
        draft.summary = "Summary"
        draft.bugDescription = "Description"
        draft.version = "Trunk"
        draft.type = "defect"
        draft.severity = "S2"
        draft.priority = "P1"
        draft.points = "3"
        draft.assignedTo = "someone@mozilla.com"
        draft.keywordsCSV = "regression, perf"
        draft.whiteboard = "[tag]"
        draft.dependsOn = [3]
        draft.seeAlso = ["https://example.com/1"]
        draft.isConfidential = true

        let copy = draft.duplicate()

        #expect(copy.id != draft.id)
        #expect(copy.product == "Firefox")
        #expect(copy.componentName == "General")
        #expect(copy.blocks == [1, 2])
        #expect(copy.summary == "Summary")
        #expect(copy.bugDescription == "Description")
        #expect(copy.version == "Trunk")
        #expect(copy.type == "defect")
        #expect(copy.severity == "S2")
        #expect(copy.priority == "P1")
        #expect(copy.points == "3")
        #expect(copy.assignedTo == "someone@mozilla.com")
        #expect(copy.keywordsCSV == "regression, perf")
        #expect(copy.whiteboard == "[tag]")
        #expect(copy.dependsOn == [3])
        #expect(copy.seeAlso == ["https://example.com/1"])
        #expect(copy.isConfidential)
    }
}
