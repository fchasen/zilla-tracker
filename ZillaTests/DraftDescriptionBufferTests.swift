import Foundation
import SwiftData
import Testing
@testable import Zilla

@MainActor
struct DraftDescriptionBufferTests {
    private let container: ModelContainer
    private let draft: BugDraft

    init() throws {
        container = try ModelContainer(
            for: BugDraft.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        draft = BugDraft(product: "Firefox", componentName: "General")
        draft.bugDescription = "start"
        draft.updatedAt = .distantPast
        container.mainContext.insert(draft)
    }

    private func settle(_ buffer: DraftDescriptionBuffer) async {
        for _ in 0..<200 where buffer.hasPendingCommit {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func editsReachTheDraftAfterTheDelay() async {
        let buffer = DraftDescriptionBuffer(draft: draft, delay: .milliseconds(10))
        buffer.edit("a")
        buffer.edit("ab")
        #expect(draft.bugDescription == "start")
        #expect(buffer.hasPendingCommit)
        await settle(buffer)
        #expect(draft.bugDescription == "ab")
        #expect(draft.updatedAt > .distantPast)
    }

    @Test func commitWritesImmediately() {
        let buffer = DraftDescriptionBuffer(draft: draft, delay: .seconds(60))
        buffer.edit("typed")
        buffer.commit()
        #expect(draft.bugDescription == "typed")
        #expect(!buffer.hasPendingCommit)
    }

    @Test func commitWithoutChangesLeavesTimestamp() {
        let buffer = DraftDescriptionBuffer(draft: draft)
        buffer.commit()
        #expect(draft.updatedAt == .distantPast)
    }

    @Test func discardDropsThePendingEdit() async {
        let buffer = DraftDescriptionBuffer(draft: draft, delay: .milliseconds(10))
        buffer.edit("gone")
        buffer.discard()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(draft.bugDescription == "start")
    }

    @Test func deletedDraftIsNotWritten() {
        let buffer = DraftDescriptionBuffer(draft: draft, delay: .seconds(60))
        buffer.edit("late")
        container.mainContext.delete(draft)
        buffer.commit()
        #expect(!buffer.hasPendingCommit)
    }

    @Test func storedChangesAreAdoptedOnlyWhenNothingIsPending() {
        let buffer = DraftDescriptionBuffer(draft: draft, delay: .seconds(60))
        buffer.adopt("external")
        #expect(buffer.text == "external")
        buffer.edit("local")
        buffer.adopt("other")
        #expect(buffer.text == "local")
    }
}
