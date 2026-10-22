//
//  BugStoreTests.swift
//  ZillaTests
//

import Testing
@testable import Zilla
import BugzillaKit
import Foundation

private typealias Bug = BugzillaKit.Bug
private typealias Comment = BugzillaKit.Comment

@MainActor
struct BugStoreTests {

    private func makeBug(
        _ id: Bug.ID,
        summary: String = "Summary",
        status: String = "NEW",
        priority: String? = "P3",
        changed: TimeInterval = 0,
        blocks: [Bug.ID] = [],
        dependsOn: [Bug.ID] = [],
        flags: [Flag] = []
    ) -> Bug {
        Bug(
            id: id,
            summary: summary,
            status: status,
            resolution: "",
            product: "Firefox",
            component: "General",
            assignedTo: "nobody@mozilla.org",
            lastChangeTime: Date(timeIntervalSince1970: changed),
            priority: priority,
            blocks: blocks,
            dependsOn: dependsOn,
            flags: flags
        )
    }

    private func load(_ comments: [Comment], for id: Bug.ID, into store: inout BugStore) {
        let ticket = store.beginFetch(id)
        store.receiveComments(comments, ticket: ticket)
        store.endFetch(ticket)
    }

    private func load(_ bug: Bug, into store: inout BugStore) {
        let ticket = store.beginFetch(bug.id)
        store.receiveBug(bug, ticket: ticket)
        store.endFetch(ticket)
    }

    private func makeComment(_ id: Comment.ID, bug: Bug.ID, text: String) -> Comment {
        Comment(id: id, bugId: bug, creator: "a@example.com", text: text, creationTime: .distantPast, isPrivate: false, count: id)
    }

    // MARK: Fetch ordering

    @Test func lateResultFromOlderFetchIsDropped() {
        var store = BugStore()
        let first = store.beginFetch(1)
        let second = store.beginFetch(1)

        let appliedNew = store.receiveBug(makeBug(1, summary: "new"), ticket: second)
        let appliedOld = store.receiveBug(makeBug(1, summary: "old"), ticket: first)

        #expect(appliedNew)
        #expect(!appliedOld)
        #expect(store.bug(1)?.summary == "new")
    }

    @Test func sameTicketDeliversARevalidatedCopy() {
        var store = BugStore()
        let ticket = store.beginFetch(1)

        store.receiveBug(makeBug(1, summary: "cached"), ticket: ticket)
        store.receiveBug(makeBug(1, summary: "revalidated"), ticket: ticket)

        #expect(store.bug(1)?.summary == "revalidated")
    }

    @Test func resultsForOneBugNeverLandOnAnother() {
        var store = BugStore()
        let a = store.beginFetch(1)
        let b = store.beginFetch(2)

        store.receiveBug(makeBug(2, summary: "two"), ticket: b)
        store.receiveBug(makeBug(1, summary: "one"), ticket: a)

        #expect(store.bug(1)?.summary == "one")
        #expect(store.bug(2)?.summary == "two")
    }

    @Test func onlyTheLatestFetchReportsAnError() {
        var store = BugStore()
        let stale = store.beginFetch(1)
        let current = store.beginFetch(1)

        store.failFetch(stale, message: "cancelled")
        #expect(store.error(1) == nil)

        store.failFetch(current, message: "offline")
        #expect(store.error(1) == "offline")

        let retry = store.beginFetch(1)
        store.receiveBug(makeBug(1), ticket: retry)
        #expect(store.error(1) == nil)
    }

    @Test func fetchingTracksEveryActiveTicket() {
        var store = BugStore()
        let first = store.beginFetch(1)
        let second = store.beginFetch(1)
        #expect(store.isFetching(1))

        store.endFetch(first)
        #expect(store.isFetching(1))

        store.endFetch(second)
        #expect(!store.isFetching(1))
    }

    @Test func seedingNeverReplacesAFetchedRecord() {
        var store = BugStore()
        let ticket = store.beginFetch(1)
        store.receiveBug(makeBug(1, summary: "fetched"), ticket: ticket)

        store.seed(makeBug(1, summary: "cached"), comments: nil)

        #expect(store.bug(1)?.summary == "fetched")
    }

    // MARK: Edits

    @Test func editShowsImmediatelyAndRevertsWhenDiscarded() {
        var store = BugStore()
        store.receiveBug(makeBug(1, priority: "P3"), ticket: store.beginFetch(1))

        let edit = store.beginEdit(1, update: BugUpdate(priority: "P1"))
        #expect(store.bug(1)?.priority == "P1")
        #expect(store.isWriting(1))

        store.discardEdit(edit)
        #expect(store.bug(1)?.priority == "P3")
        #expect(!store.isWriting(1))
    }

    @Test func confirmedEditSurvivesAFetchThatStartedBeforeIt() {
        var store = BugStore()
        store.receiveBug(makeBug(1, priority: "P3"), ticket: store.beginFetch(1))

        let edit = store.beginEdit(1, update: BugUpdate(priority: "P1"))
        let inflight = store.beginFetch(1)
        store.confirmEdit(edit)
        store.receiveBug(makeBug(1, priority: "P3"), ticket: inflight)

        #expect(store.bug(1)?.priority == "P1")
    }

    @Test func confirmedEditDropsOnceAFetchStartedAfterItLands() {
        var store = BugStore()
        store.receiveBug(makeBug(1, priority: "P3"), ticket: store.beginFetch(1))

        let edit = store.beginEdit(1, update: BugUpdate(priority: "P1"))
        store.confirmEdit(edit)
        let refresh = store.beginFetch(1)
        store.receiveBug(makeBug(1, priority: "P1"), ticket: refresh)

        #expect(store.edits[1] == nil)
        #expect(store.bug(1)?.priority == "P1")
        #expect(!store.isWriting(1))
    }

    @Test func unconfirmedEditOutlivesAnyFetch() {
        var store = BugStore()
        let edit = store.beginEdit(1, update: BugUpdate(status: "ASSIGNED"))
        let later = store.beginFetch(1)
        store.receiveBug(makeBug(1, status: "NEW"), ticket: later)

        #expect(store.bug(1)?.status == "ASSIGNED")
        store.discardEdit(edit)
        #expect(store.bug(1)?.status == "NEW")
    }

    @Test func settlingFoldsTheEditWhenNoRefreshArrived() {
        var store = BugStore()
        store.receiveBug(makeBug(1, summary: "before"), ticket: store.beginFetch(1))

        let edit = store.beginEdit(1, update: BugUpdate(summary: "after"))
        store.confirmEdit(edit)
        store.settleEdit(edit)

        #expect(store.edits[1] == nil)
        #expect(store.bug(1)?.summary == "after")
    }

    @Test func settlingAnUnconfirmedEditDoesNothing() {
        var store = BugStore()
        store.receiveBug(makeBug(1, summary: "before"), ticket: store.beginFetch(1))
        let edit = store.beginEdit(1, update: BugUpdate(summary: "after"))

        store.settleEdit(edit)

        #expect(store.edits[1]?.count == 1)
    }

    @Test func overlappingEditsApplyInOrder() {
        var store = BugStore()
        store.receiveBug(makeBug(1, priority: "P3"), ticket: store.beginFetch(1))

        let first = store.beginEdit(1, update: BugUpdate(priority: "P2"))
        _ = store.beginEdit(1, update: BugUpdate(priority: "P1"))
        #expect(store.bug(1)?.priority == "P1")

        store.confirmEdit(first)
        store.receiveBug(makeBug(1, priority: "P2"), ticket: store.beginFetch(1))
        #expect(store.bug(1)?.priority == "P1")
    }

    // MARK: Display merging

    @Test func listRowUsesTheNewerOfRowAndRecord() {
        var store = BugStore()
        store.receiveBug(makeBug(1, summary: "record", changed: 100), ticket: store.beginFetch(1))

        #expect(store.displayed(makeBug(1, summary: "older row", changed: 50)).summary == "record")
        #expect(store.displayed(makeBug(1, summary: "same row", changed: 100)).summary == "record")
        #expect(store.displayed(makeBug(1, summary: "newer row", changed: 200)).summary == "newer row")
    }

    @Test func listRowCarriesPendingEdits() {
        var store = BugStore()
        _ = store.beginEdit(7, update: BugUpdate(status: "RESOLVED", resolution: "FIXED"))

        let row = store.displayed(makeBug(7, status: "NEW"))

        #expect(row.status == "RESOLVED")
        #expect(row.resolution == "FIXED")
    }

    // MARK: Comments

    @Test func pendingCommentAppearsUntilARefreshIncludesIt() {
        var store = BugStore()
        let load = store.beginFetch(1)
        store.receiveComments([makeComment(10, bug: 1, text: "first")], ticket: load)

        let comment = store.beginComment(1, author: "me@example.com", text: "hello")
        #expect(store.comments(1).map(\.text) == ["first", "hello"])
        #expect(store.comments(1).last.map { $0.id < 0 } == true)

        store.confirmComment(comment)
        let refresh = store.beginFetch(1)
        store.receiveComments(
            [makeComment(10, bug: 1, text: "first"), makeComment(11, bug: 1, text: "hello")],
            ticket: refresh
        )

        #expect(store.comments(1).map(\.id) == [10, 11])
    }

    @Test func failedCommentDisappears() {
        var store = BugStore()
        let comment = store.beginComment(1, author: "me@example.com", text: "hello")
        #expect(store.isWriting(1))

        store.discardComment(comment)

        #expect(store.comments(1).isEmpty)
        #expect(!store.isWriting(1))
    }

    @Test func commentEditReplacesTextUntilSettled() {
        var store = BugStore()
        store.receiveComments([makeComment(10, bug: 1, text: "typo")], ticket: store.beginFetch(1))

        let edit = store.beginCommentEdit(1, commentID: 10, text: "fixed")
        #expect(store.comments(1).first?.text == "fixed")

        store.confirmCommentEdit(edit)
        store.settleCommentEdit(edit)

        #expect(store.commentEdits[1] == nil)
        #expect(store.comments(1).first?.text == "fixed")
    }

    @Test func failedCommentEditRestoresText() {
        var store = BugStore()
        store.receiveComments([makeComment(10, bug: 1, text: "original")], ticket: store.beginFetch(1))

        let edit = store.beginCommentEdit(1, commentID: 10, text: "edited")
        store.discardCommentEdit(edit)

        #expect(store.comments(1).first?.text == "original")
    }

    // MARK: Retention

    @Test func presentedBugsKeepTheirComments() {
        var store = BugStore()
        store.present(1)
        load([makeComment(1, bug: 1, text: "keep")], for: 1, into: &store)

        for id in 2...(BugStore.retainedCommentLimit + 5) {
            load([makeComment(id, bug: id, text: "x")], for: id, into: &store)
        }

        #expect(store.hasComments(1))
        #expect(!store.hasComments(2))
        #expect(store.hasComments(BugStore.retainedCommentLimit + 5))
    }

    @Test func dismissedBugBecomesEvictable() {
        var store = BugStore()
        store.present(1)
        load([makeComment(1, bug: 1, text: "x")], for: 1, into: &store)
        store.dismiss(1)

        for id in 2...(BugStore.retainedCommentLimit + 1) {
            load([makeComment(id, bug: id, text: "x")], for: id, into: &store)
        }

        #expect(!store.hasComments(1))
    }

    @Test func bugWithPendingEditIsNotEvicted() {
        var store = BugStore()
        load(makeBug(1), into: &store)
        _ = store.beginEdit(1, update: BugUpdate(priority: "P1"))

        for id in 2...(BugStore.retainedBugLimit + 5) {
            load(makeBug(id), into: &store)
        }

        #expect(store.bug(1)?.priority == "P1")
        #expect(store.bug(2) == nil)
    }

    // MARK: Applying updates

    @Test func applyingAssigneeUsesSuppliedDetail() {
        let user = User(id: 5, name: "dev@example.com", realName: "Dev Person")

        let bug = makeBug(1).applying(BugUpdate(status: "ASSIGNED", assignedTo: "dev@example.com"), users: [user])

        #expect(bug.status == "ASSIGNED")
        #expect(bug.assignedTo == "dev@example.com")
        #expect(bug.assignedToDetail == user)
    }

    @Test func applyingKeywordsAddsAndRemoves() {
        let added = makeBug(1).applying(BugUpdate(keywords: .add(["regression", "perf"])))
        #expect(added.keywords == ["regression", "perf"])
        let removed = added.applying(BugUpdate(keywords: .remove(["regression"])))
        #expect(removed.keywords == ["perf"])
    }

    @Test func applyingDuplicateSetsResolution() {
        let bug = makeBug(1).applying(BugUpdate(status: "RESOLVED", dupeOf: 9))
        #expect(bug.resolution == "DUPLICATE")
    }

    @Test func applyingRankZeroClearsRank() {
        let bug = makeBug(1).applying(BugUpdate(rank: 0))
        #expect(bug.rank == nil)
    }

    @Test func applyingRelationsAddsAndRemoves() {
        let bug = makeBug(1, blocks: [2, 3], dependsOn: [4])
            .applying(BugUpdate(blocks: .remove([2]), dependsOn: .add([5, 4])))

        #expect(bug.blocks == [3])
        #expect(bug.dependsOn == [4, 5])
    }

    @Test func applyingFlagUpdates() {
        let existing = Flag(id: 30, name: "qe-verify", status: "+")
        let needinfo = Flag(id: 31, name: "needinfo", status: "?", requestee: "a@example.com")
        let bug = makeBug(1, flags: [existing, needinfo]).applying(
            BugUpdate(flags: [
                FlagUpdate(id: 30, status: "-"),
                FlagUpdate(id: 31, status: "X"),
                FlagUpdate(name: "needinfo", status: "?", requestee: "b@example.com")
            ]),
            editID: 3
        )

        #expect(bug.flags.count == 2)
        #expect(bug.flags[0].status == "-")
        #expect(bug.flags[1].name == "needinfo")
        #expect(bug.flags[1].requestee == "b@example.com")
        #expect(bug.flags[1].id < 0)
    }

    @Test func relationUpdatesMirrorOntoTheOtherBug() {
        let update = BugUpdate(blocks: .add([2]), dependsOn: .remove([3]))

        let mirrors = update.mirroredRelations(for: 1)

        #expect(mirrors[2]?.dependsOn?.add == [1])
        #expect(mirrors[3]?.blocks?.remove == [1])
        #expect(mirrors.count == 2)
    }

    // MARK: Workspace focus

    @Test func focusFollowsTheTopOfTheDetailStack() {
        let workspace = Workspace()
        workspace.sidebarSelection = .smart(.myBugs)
        workspace.selectedBugID = 10
        #expect(workspace.focusedBugID == 10)

        workspace.navigate(to: .bug(20))
        #expect(workspace.focusedBugID == 20)

        workspace.navigate(to: .revision(5))
        #expect(workspace.focusedBugID == nil)
        #expect(workspace.focusedRevisionID == 5)

        workspace.detailPath = []
        #expect(workspace.focusedBugID == 10)
        #expect(workspace.focusedRevisionID == nil)
    }
}
