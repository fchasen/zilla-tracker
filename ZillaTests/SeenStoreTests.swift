import Foundation
import Testing
import BugzillaKit
@testable import Zilla

private typealias Bug = BugzillaKit.Bug

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func date(_ offset: TimeInterval) -> Date {
    now.addingTimeInterval(offset)
}

private func makeDefaults() -> UserDefaults {
    let suite = "SeenStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
struct SeenStoreMergeTests {
    @Test func newerRecordWins() {
        let local = [1: SeenMark(seenThrough: date(-100), recordedAt: date(-100))]
        let remote = [1: SeenMark(seenThrough: nil, recordedAt: date(-50))]
        let merged = ViewedBugsStore.merged(local, with: remote, now: now)
        #expect(merged[1]?.isViewed == false)
    }

    @Test func olderRemoteRecordLoses() {
        let local = [1: SeenMark(seenThrough: nil, recordedAt: date(-50))]
        let remote = [1: SeenMark(seenThrough: date(-100), recordedAt: date(-100))]
        let merged = ViewedBugsStore.merged(local, with: remote, now: now)
        #expect(merged[1]?.isViewed == false)
    }

    @Test func tiedRecordsResolveTheSameWayOnBothSides() {
        let viewed = [1: SeenMark(seenThrough: date(-10), recordedAt: date(-10))]
        let unviewed = [1: SeenMark(seenThrough: nil, recordedAt: date(-10))]
        let a = ViewedBugsStore.merged(viewed, with: unviewed, now: now)
        let b = ViewedBugsStore.merged(unviewed, with: viewed, now: now)
        #expect(a == b)
    }

    @Test func expiredRecordsAreDropped() {
        let expired = date(-ViewedBugsStore.retention - 60)
        let local = [1: SeenMark(seenThrough: expired, recordedAt: expired)]
        let remote = [2: SeenMark(seenThrough: expired, recordedAt: expired)]
        #expect(ViewedBugsStore.merged(local, with: remote, now: now).isEmpty)
    }

    @Test func pruningKeepsNewestEntries() {
        let count = ViewedBugsStore.maxEntries + 5
        let marks = Dictionary(uniqueKeysWithValues: (0..<count).map { id in
            (id, SeenMark(seenThrough: date(TimeInterval(-id)), recordedAt: date(TimeInterval(-id))))
        })
        let pruned = ViewedBugsStore.pruned(marks, now: now)
        #expect(pruned.count == ViewedBugsStore.maxEntries)
        #expect(pruned[0] != nil)
        #expect(pruned[count - 1] == nil)
    }
}

@MainActor
struct SeenStoreTests {
    @Test func migratesLegacyIDsAsSeenAtLaunch() throws {
        let defaults = makeDefaults()
        defaults.set([10, 20], forKey: SeenBugs.legacyStorageKey)
        let store = ViewedBugsStore(defaults: defaults, cloud: nil, now: now)
        #expect(store.ids == [10, 20])
        #expect(store.mark(for: 10)?.seenThrough == now)
        #expect(defaults.data(forKey: SeenBugs.storageKey) != nil)
    }

    @Test func storedMarksTakePrecedenceOverLegacyIDs() throws {
        let defaults = makeDefaults()
        defaults.set([10, 20], forKey: SeenBugs.legacyStorageKey)
        let stored = [30: SeenMark(seenThrough: date(-60), recordedAt: date(-60))]
        defaults.set(try JSONEncoder().encode(stored), forKey: SeenBugs.storageKey)
        let store = ViewedBugsStore(defaults: defaults, cloud: nil, now: now)
        #expect(store.ids == [30])
        #expect(store.mark(for: 30)?.seenThrough == date(-60))
    }

    @Test func markViewedNeverMovesTheWatermarkBackward() {
        let store = ViewedBugsStore(defaults: makeDefaults(), cloud: nil, now: now)
        store.markViewed(1, through: date(100))
        store.markViewed(1, through: date(50))
        #expect(store.mark(for: 1)?.seenThrough == date(100))
    }

    @Test func markUnviewedKeepsAnUnviewedRecord() {
        let store = ViewedBugsStore(defaults: makeDefaults(), cloud: nil, now: now)
        store.markViewed(1, through: date(0))
        store.markUnviewed(1)
        #expect(store.contains(1) == false)
        #expect(store.mark(for: 1)?.isViewed == false)
        #expect(store.ids.isEmpty)
    }

    @Test func advanceIfViewedLeavesUnseenItemsAlone() {
        let store = ViewedBugsStore(defaults: makeDefaults(), cloud: nil, now: now)
        store.advanceIfViewed(1, through: date(0))
        #expect(store.mark(for: 1) == nil)
        store.markViewed(2, through: date(0))
        store.advanceIfViewed(2, through: date(30))
        #expect(store.mark(for: 2)?.seenThrough == date(30))
    }
}

@MainActor
struct BugAttentionTests {
    private func makeBug(
        status: String = "NEW",
        created: Date? = date(-2 * 24 * 60 * 60),
        changed: Date? = date(-60),
        flags: [Flag] = []
    ) -> Bug {
        Bug(
            id: 1,
            summary: "Bug",
            status: status,
            resolution: "",
            product: "Firefox",
            component: "General",
            creationTime: created,
            lastChangeTime: changed,
            flags: flags
        )
    }

    private func needinfo(
        requestee: String = "me@mozilla.com",
        status: String = "?",
        created: Date = date(-60),
        modified: Date? = nil
    ) -> Flag {
        Flag(
            id: 7,
            name: "needinfo",
            status: status,
            setter: "someone@mozilla.com",
            requestee: requestee,
            creationDate: created,
            modificationDate: modified
        )
    }

    private func oldBug(_ flags: [Flag]) -> Bug {
        makeBug(created: date(-90 * 24 * 60 * 60), changed: date(-60), flags: flags)
    }

    @Test func recentUnseenOpenBugNeedsAttention() {
        #expect(BugAttention.needsAttention(makeBug(), mark: nil, viewer: nil, now: now))
    }

    @Test func olderUnseenBugDoesNot() {
        let bug = makeBug(created: date(-10 * 24 * 60 * 60))
        #expect(!BugAttention.needsAttention(bug, mark: nil, viewer: nil, now: now))
    }

    @Test func unseenClosedBugDoesNot() {
        #expect(!BugAttention.needsAttention(makeBug(status: "RESOLVED"), mark: nil, viewer: nil, now: now))
    }

    @Test func viewedBugChangedSinceNeedsAttention() {
        let mark = SeenMark(seenThrough: date(-120), recordedAt: date(-120))
        #expect(BugAttention.needsAttention(makeBug(changed: date(-60)), mark: mark, viewer: nil, now: now))
    }

    @Test func viewedBugUnchangedSinceDoesNot() {
        let mark = SeenMark(seenThrough: date(-30), recordedAt: date(-30))
        #expect(!BugAttention.needsAttention(makeBug(changed: date(-60)), mark: mark, viewer: nil, now: now))
    }

    @Test func unseenRequestOnOldBugNeedsAttention() {
        let bug = oldBug([needinfo()])
        #expect(BugAttention.hasUnseenRequest(bug, for: "me@mozilla.com", mark: nil))
        #expect(BugAttention.needsAttention(bug, mark: nil, viewer: "me@mozilla.com", now: now))
        #expect(!BugAttention.needsAttention(bug, mark: nil, viewer: nil, now: now))
    }

    @Test func requestSeenSinceDoesNotCount() {
        let mark = SeenMark(seenThrough: date(-30), recordedAt: date(-30))
        #expect(!BugAttention.hasUnseenRequest(oldBug([needinfo(created: date(-60))]), for: "me@mozilla.com", mark: mark))
    }

    @Test func requestAfterLastViewCounts() {
        let mark = SeenMark(seenThrough: date(-120), recordedAt: date(-120))
        #expect(BugAttention.hasUnseenRequest(oldBug([needinfo(created: date(-60))]), for: "me@mozilla.com", mark: mark))
    }

    @Test func reRequestUsesModificationDate() {
        let mark = SeenMark(seenThrough: date(-120), recordedAt: date(-120))
        let flag = needinfo(created: date(-1000), modified: date(-60))
        #expect(BugAttention.hasUnseenRequest(oldBug([flag]), for: "me@mozilla.com", mark: mark))
    }

    @Test func requestsForOthersOrResolvedFlagsDoNotCount() {
        #expect(!BugAttention.hasUnseenRequest(oldBug([needinfo(requestee: "other@mozilla.com")]), for: "me@mozilla.com", mark: nil))
        #expect(!BugAttention.hasUnseenRequest(oldBug([needinfo(status: "+")]), for: "me@mozilla.com", mark: nil))
    }

    @Test func requesteeMatchIgnoresCase() {
        #expect(BugAttention.hasUnseenRequest(oldBug([needinfo(requestee: "Me@Mozilla.com")]), for: "me@mozilla.com", mark: nil))
    }

    @Test func markedUnviewedBugNeedsAttention() {
        let mark = SeenMark(seenThrough: nil, recordedAt: date(-30))
        let bug = makeBug(created: date(-30 * 24 * 60 * 60), changed: date(-20 * 24 * 60 * 60))
        #expect(BugAttention.needsAttention(bug, mark: mark, viewer: nil, now: now))
    }
}
