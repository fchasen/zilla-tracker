import Foundation
import Testing
import BugzillaKit
import PhabricatorKit
@testable import Zilla

private let viewer = "me@example.com"
private let base: TimeInterval = 1_800_000_000

private func at(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: base + offset)
}

private func needinfoFlag(
    id: Int = 1,
    requestee: String = viewer,
    setter: String? = "jdoe@example.com",
    status: String = "?",
    at offset: TimeInterval
) -> Flag {
    Flag(
        id: id,
        name: "needinfo",
        status: status,
        setter: setter,
        requestee: requestee,
        creationDate: at(offset),
        modificationDate: at(offset)
    )
}

private func makeBug(id: Int = 1923456, summary: String = "Crash in LoadURI", flags: [Flag]) -> BugzillaKit.Bug {
    BugzillaKit.Bug(
        id: id,
        summary: summary,
        status: "NEW",
        resolution: "",
        product: "Core",
        component: "DOM",
        lastChangeTime: at(500),
        flags: flags
    )
}

private func makeRevision(
    id: Int = 224113,
    title: String = "Bug 1923456 - Fix crash in LoadURI",
    author: String = "PHID-USER-author",
    created: TimeInterval = 0,
    modified: TimeInterval = 400
) throws -> Revision {
    let json = Data(#"""
    {
      "id": \#(id),
      "phid": "PHID-DREV-\#(id)",
      "fields": {
        "title": "\#(title)",
        "authorPHID": "\#(author)",
        "status": {"value":"needs-review","name":"Needs Review","closed":false},
        "isDraft": false,
        "dateCreated": \#(Int(base + created)),
        "dateModified": \#(Int(base + modified))
      }
    }
    """#.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(Revision.self, from: json)
}

@MainActor
struct NeedinfoCandidateTests {
    @Test func buildsCandidateForUnseenRequest() throws {
        let bug = makeBug(flags: [needinfoFlag(at: 100)])
        let candidate = try #require(AttentionCandidates.needinfo(bug, viewer: viewer, mark: nil))
        #expect(candidate.category == .needinfo)
        #expect(candidate.itemID == 1923456)
        #expect(candidate.identifier == "needinfo-1923456")
        #expect(candidate.eventDate == at(100))
        #expect(candidate.title == "Needinfo from jdoe@example.com")
        #expect(candidate.subtitle == "Bug 1923456")
        #expect(candidate.body == "Crash in LoadURI")
        #expect(candidate.url == URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=1923456"))
    }

    @Test func usesSetterOfLatestRequest() throws {
        let bug = makeBug(flags: [
            needinfoFlag(id: 1, setter: "early@example.com", at: 100),
            needinfoFlag(id: 2, setter: "late@example.com", at: 300),
            needinfoFlag(id: 3, requestee: "other@example.com", setter: "other-setter@example.com", at: 400)
        ])
        let candidate = try #require(AttentionCandidates.needinfo(bug, viewer: viewer, mark: nil))
        #expect(candidate.eventDate == at(300))
        #expect(candidate.title == "Needinfo from late@example.com")
    }

    @Test func fallsBackWhenSetterMissing() throws {
        let missing = makeBug(flags: [needinfoFlag(setter: nil, at: 100)])
        let empty = makeBug(flags: [needinfoFlag(setter: "", at: 100)])
        #expect(AttentionCandidates.needinfo(missing, viewer: viewer, mark: nil)?.title == "Needinfo request")
        #expect(AttentionCandidates.needinfo(empty, viewer: viewer, mark: nil)?.title == "Needinfo request")
    }

    @Test func matchesRequesteeCaseInsensitively() {
        let bug = makeBug(flags: [needinfoFlag(requestee: "ME@Example.com", at: 100)])
        #expect(AttentionCandidates.needinfo(bug, viewer: viewer, mark: nil) != nil)
    }

    @Test func skipsSeenRequests() {
        let bug = makeBug(flags: [needinfoFlag(at: 100)])
        let seen = SeenMark(seenThrough: at(200), recordedAt: at(200))
        let stale = SeenMark(seenThrough: at(50), recordedAt: at(50))
        #expect(AttentionCandidates.needinfo(bug, viewer: viewer, mark: seen) == nil)
        #expect(AttentionCandidates.needinfo(bug, viewer: viewer, mark: stale) != nil)
    }

    @Test func skipsRequestsForOthersAndGrantedFlags() {
        let other = makeBug(flags: [needinfoFlag(requestee: "other@example.com", at: 100)])
        let granted = makeBug(flags: [needinfoFlag(status: "+", at: 100)])
        #expect(AttentionCandidates.needinfo(other, viewer: viewer, mark: nil) == nil)
        #expect(AttentionCandidates.needinfo(granted, viewer: viewer, mark: nil) == nil)
    }

    @Test func filtersListUsingMarks() {
        let unseen = makeBug(id: 1, flags: [needinfoFlag(at: 100)])
        let seen = makeBug(id: 2, flags: [needinfoFlag(at: 100)])
        let none = makeBug(id: 3, flags: [])
        let candidates = AttentionCandidates.needinfo(
            [unseen, seen, none],
            viewer: viewer,
            marks: [2: SeenMark(seenThrough: at(200), recordedAt: at(200))]
        )
        #expect(candidates.map(\.itemID) == [1])
    }
}

@MainActor
struct ReviewCandidateTests {
    @Test func buildsCandidateForUnseenReview() throws {
        let revision = try makeRevision(created: 10)
        let candidate = try #require(AttentionCandidates.review(
            revision,
            mark: nil,
            activity: nil,
            authorName: "asmith"
        ))
        #expect(candidate.category == .review)
        #expect(candidate.identifier == "review-224113")
        #expect(candidate.eventDate == at(10))
        #expect(candidate.title == "Review requested by asmith")
        #expect(candidate.subtitle == "D224113")
        #expect(candidate.body == "Bug 1923456 - Fix crash in LoadURI")
        #expect(candidate.url == URL(string: "https://phabricator.services.mozilla.com/D224113"))
    }

    @Test func fallsBackWhenAuthorUnknown() throws {
        let revision = try makeRevision()
        let candidate = AttentionCandidates.review(revision, mark: nil, activity: nil, authorName: nil)
        #expect(candidate?.title == "Review requested by Someone")
    }

    @Test func usesLatestActivityFromOthersAsEventDate() throws {
        let revision = try makeRevision(created: 10, modified: 400)
        let activity = RevisionActivity(dateModified: at(400), latestFromViewer: nil, latestFromOthers: at(350))
        let mark = SeenMark(seenThrough: at(200), recordedAt: at(200))
        let candidate = try #require(AttentionCandidates.review(
            revision,
            mark: mark,
            activity: activity,
            authorName: "asmith"
        ))
        #expect(candidate.eventDate == at(350))
    }

    @Test func skipsSeenReviewWithoutNewActivity() throws {
        let revision = try makeRevision(modified: 400)
        let activity = RevisionActivity(dateModified: at(400), latestFromViewer: nil, latestFromOthers: at(150))
        let mark = SeenMark(seenThrough: at(200), recordedAt: at(200))
        #expect(AttentionCandidates.review(revision, mark: mark, activity: activity, authorName: nil) == nil)
        #expect(AttentionCandidates.review(revision, mark: mark, activity: nil, authorName: nil) == nil)
    }

    @Test func includesReviewMarkedUnread() throws {
        let revision = try makeRevision(created: 10)
        let unread = SeenMark(seenThrough: nil, recordedAt: at(200))
        let candidate = AttentionCandidates.review(revision, mark: unread, activity: nil, authorName: nil)
        #expect(candidate?.eventDate == at(10))
    }

    @Test func filtersListAndResolvesAuthors() throws {
        let fresh = try makeRevision(id: 1, author: "PHID-USER-a")
        let seen = try makeRevision(id: 2, author: "PHID-USER-b")
        let candidates = AttentionCandidates.reviews(
            [fresh, seen],
            marks: [2: SeenMark(seenThrough: at(500), recordedAt: at(500))],
            activity: [:],
            usernames: ["PHID-USER-a": "alice", "PHID-USER-b": "bob"]
        )
        #expect(candidates.map(\.itemID) == [1])
        #expect(candidates.first?.title == "Review requested by alice")
    }
}

@MainActor
struct PatchCandidateTests {
    @Test func buildsCandidateFromEvent() throws {
        let revision = try makeRevision(id: 223901, title: "Bug 1910022 - Tidy toolbar layout")
        let event = RevisionEvent(actorPHID: "PHID-USER-m", kind: .accepted, date: at(250))
        let candidate = AttentionCandidates.patch(revision, event: event, actorName: "mconley")
        #expect(candidate.category == .patch)
        #expect(candidate.identifier == "patch-223901")
        #expect(candidate.eventDate == at(250))
        #expect(candidate.title == "mconley accepted your revision")
        #expect(candidate.subtitle == "D223901")
        #expect(candidate.body == "Bug 1910022 - Tidy toolbar layout")
        #expect(candidate.url == URL(string: "https://phabricator.services.mozilla.com/D223901"))
    }

    @Test func fallsBackWhenActorUnknown() throws {
        let revision = try makeRevision()
        let event = RevisionEvent(actorPHID: "PHID-USER-x", kind: .commented, date: at(250))
        #expect(AttentionCandidates.patch(revision, event: event, actorName: nil).title == "Someone commented on your revision")
    }

    @Test(arguments: [
        (RevisionEventKind.accepted, "accepted your revision"),
        (.requestedChanges, "requested changes to your revision"),
        (.resigned, "resigned from your revision"),
        (.commandeered, "commandeered your revision"),
        (.commented, "commented on your revision"),
        (.inlineCommented, "left inline comments on your revision"),
        (.landed, "landed your revision"),
        (.abandoned, "abandoned your revision"),
        (.reclaimed, "reclaimed your revision"),
        (.reopened, "reopened your revision"),
        (.statusChanged("needs-revision"), "changed your revision's status to Needs Revision"),
        (.statusChanged("published"), "changed your revision's status to Closed"),
        (.statusChanged("custom-state"), "changed your revision's status to custom-state"),
        (.statusChanged(nil), "changed your revision's status"),
        (.statusChanged(""), "changed your revision's status")
    ])
    func phrases(kind: RevisionEventKind, phrase: String) {
        #expect(AttentionCandidates.phrase(for: kind) == phrase)
    }

    @Test func skipsRevisionsWithoutNotifiableEvent() throws {
        let revision = try makeRevision()
        let activity = RevisionActivity(dateModified: at(400), latestFromViewer: nil, latestFromOthers: at(300))
        let candidates = AttentionCandidates.patches(
            [revision],
            marks: [:],
            activity: [revision.id: activity],
            usernames: [:]
        )
        #expect(candidates.isEmpty)
    }
}
