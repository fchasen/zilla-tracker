import Foundation
import Testing
@testable import Zilla

private let base: TimeInterval = 1_800_000_000
private let now = at(100 * 24 * 60 * 60)

@MainActor
private var everyCategory: Set<NotificationCategory> { Set(NotificationCategory.allCases) }

private func at(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: base + offset)
}

@MainActor
private func candidate(
    _ category: NotificationCategory,
    _ itemID: Int,
    at offset: TimeInterval,
    title: String = "Title"
) -> NotificationCandidate {
    NotificationCandidate(
        category: category,
        itemID: itemID,
        eventDate: at(offset),
        title: title,
        subtitle: "Subtitle",
        body: "Body",
        url: URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(itemID)")!
    )
}

@MainActor
private func entry(at offset: TimeInterval, recorded: Date = now) -> NotifiedEntry {
    NotifiedEntry(eventDate: at(offset), recordedAt: recorded)
}

@MainActor
private func baselined(_ entries: [String: NotifiedEntry] = [:]) -> NotificationLedger {
    NotificationLedger(entries: entries, baselined: everyCategory)
}

@MainActor
private func plan(
    _ candidates: [NotificationCandidate],
    polled: Set<NotificationCategory>? = nil,
    ledger: NotificationLedger? = nil,
    delivered: Set<String> = [],
    enabled: Set<NotificationCategory>? = nil,
    suppressed: Set<String> = []
) -> NotificationPlan {
    NotificationPlanner.plan(
        snapshot: NotificationSnapshot(candidates: candidates, polled: polled ?? everyCategory),
        ledger: ledger ?? baselined(),
        delivered: delivered,
        enabled: enabled ?? everyCategory,
        suppressed: suppressed,
        now: now
    )
}

@MainActor
struct NotificationPlannerBaselineTests {
    @Test func firstPollRecordsSilently() {
        let result = plan(
            [candidate(.needinfo, 1, at: 100), candidate(.needinfo, 2, at: 200)],
            polled: [.needinfo],
            ledger: NotificationLedger()
        )
        #expect(result.post.isEmpty)
        #expect(result.ledger.baselined == [.needinfo])
        #expect(result.ledger.entries == [
            "needinfo-1": NotifiedEntry(eventDate: at(100), recordedAt: now),
            "needinfo-2": NotifiedEntry(eventDate: at(200), recordedAt: now)
        ])
    }

    @Test func laterCategoryBaselinesOnItsFirstPoll() {
        let ledger = NotificationLedger(entries: ["needinfo-1": entry(at: 100)], baselined: [.needinfo])
        let result = plan(
            [candidate(.needinfo, 1, at: 100), candidate(.needinfo, 2, at: 300), candidate(.review, 5, at: 50)],
            polled: [.needinfo, .review],
            ledger: ledger
        )
        #expect(result.post.map(\.identifier) == ["needinfo-2"])
        #expect(result.ledger.baselined == [.needinfo, .review])
        #expect(result.ledger.entries["review-5"] == NotifiedEntry(eventDate: at(50), recordedAt: now))
    }

    @Test func unpolledCategoryStaysUnbaselined() {
        let result = plan([candidate(.needinfo, 1, at: 100)], polled: [.needinfo], ledger: NotificationLedger())
        #expect(!result.ledger.baselined.contains(.review))
        #expect(!result.ledger.baselined.contains(.patch))
    }
}

@MainActor
struct NotificationPlannerPostingTests {
    @Test func postsNewCandidate() {
        let result = plan([candidate(.patch, 3, at: 100)])
        #expect(result.post.map(\.identifier) == ["patch-3"])
        #expect(result.ledger.entries["patch-3"] == NotifiedEntry(eventDate: at(100), recordedAt: now))
    }

    @Test func repostsWhenEventIsNewer() {
        let result = plan(
            [candidate(.patch, 3, at: 200, title: "Accepted")],
            ledger: baselined(["patch-3": entry(at: 100)])
        )
        #expect(result.post.map(\.title) == ["Accepted"])
        #expect(result.ledger.entries["patch-3"] == NotifiedEntry(eventDate: at(200), recordedAt: now))
    }

    @Test func skipsEqualOrOlderEvents() {
        let entries = ["patch-3": entry(at: 200), "needinfo-4": entry(at: 200)]
        let result = plan(
            [candidate(.patch, 3, at: 200), candidate(.needinfo, 4, at: 100)],
            ledger: baselined(entries)
        )
        #expect(result.post.isEmpty)
        #expect(result.ledger.entries == entries)
    }

    @Test func suppressedCandidateRecordsSilently() {
        let first = plan([candidate(.needinfo, 7, at: 100)], suppressed: ["needinfo-7"])
        #expect(first.post.isEmpty)
        #expect(first.ledger.entries["needinfo-7"]?.eventDate == at(100))

        let second = plan([candidate(.needinfo, 7, at: 100)], ledger: first.ledger)
        #expect(second.post.isEmpty)
    }

    @Test func disabledCategoryRecordsSilently() {
        let result = plan(
            [candidate(.patch, 3, at: 100)],
            enabled: [.needinfo, .review]
        )
        #expect(result.post.isEmpty)
        #expect(result.ledger.entries["patch-3"]?.eventDate == at(100))
    }

    @Test func duplicateIdentifiersKeepLatestEvent() {
        let result = plan([
            candidate(.patch, 3, at: 200, title: "Newer"),
            candidate(.patch, 3, at: 100, title: "Older")
        ])
        #expect(result.post.map(\.title) == ["Newer"])
        #expect(result.ledger.entries["patch-3"]?.eventDate == at(200))
    }

    @Test func postsOrderedByEventDateThenIdentifier() {
        let result = plan([
            candidate(.patch, 1, at: 300),
            candidate(.review, 9, at: 100),
            candidate(.needinfo, 5, at: 100)
        ])
        #expect(result.post.map(\.identifier) == ["needinfo-5", "review-9", "patch-1"])
    }
}

@MainActor
struct NotificationPlannerRemovalTests {
    @Test func removesResolvedItems() {
        let entries = ["needinfo-1": entry(at: 100, recorded: now), "needinfo-2": entry(at: 100, recorded: now)]
        let result = plan(
            [candidate(.needinfo, 2, at: 100)],
            ledger: baselined(entries),
            delivered: ["needinfo-1", "needinfo-2"]
        )
        #expect(result.remove == ["needinfo-1"])
        #expect(result.ledger.entries == entries)
    }

    @Test func disabledCategoryRemovesDelivered() {
        let result = plan(
            [candidate(.patch, 3, at: 100), candidate(.needinfo, 1, at: 100)],
            ledger: baselined(["needinfo-1": entry(at: 100)]),
            delivered: ["patch-3", "needinfo-1"],
            enabled: [.needinfo, .review]
        )
        #expect(result.remove == ["patch-3"])
    }

    @Test func disabledUnpolledCategoryRemovesDelivered() {
        let result = plan(
            [],
            polled: [.needinfo],
            delivered: ["review-2"],
            enabled: [.needinfo, .patch]
        )
        #expect(result.remove == ["review-2"])
    }

    @Test func removalIsSortedAndIgnoresUnparseableIdentifiers() {
        let result = plan(
            [],
            delivered: ["review-3", "needinfo-8", "bogus", "unknown-4", "patch-x"]
        )
        #expect(result.remove == ["needinfo-8", "review-3"])
    }
}

@MainActor
struct NotificationPlannerUnpolledTests {
    @Test func unpolledCategoryIsUntouched() {
        let stale = entry(at: 100, recorded: now.addingTimeInterval(-NotificationPlanner.retention - 1))
        let result = plan(
            [candidate(.needinfo, 1, at: 100), candidate(.review, 8, at: 100)],
            polled: [.needinfo],
            ledger: baselined(["review-4": stale]),
            delivered: ["review-4"]
        )
        #expect(result.post.map(\.identifier) == ["needinfo-1"])
        #expect(result.remove.isEmpty)
        #expect(result.ledger.entries["review-4"] == stale)
        #expect(result.ledger.entries["review-8"] == nil)
    }
}

@MainActor
struct NotificationPlannerPruningTests {
    @Test func prunesStaleEntriesOutsideCurrentCandidates() {
        let cutoff = now.addingTimeInterval(-NotificationPlanner.retention)
        let stale = entry(at: 100, recorded: cutoff.addingTimeInterval(-1))
        let boundary = entry(at: 100, recorded: cutoff)
        let result = plan(
            [candidate(.needinfo, 2, at: 100)],
            ledger: baselined([
                "needinfo-1": stale,
                "needinfo-2": stale,
                "needinfo-3": boundary
            ])
        )
        #expect(result.ledger.entries["needinfo-1"] == nil)
        #expect(result.ledger.entries["needinfo-2"] == stale)
        #expect(result.ledger.entries["needinfo-3"] == boundary)
    }
}
