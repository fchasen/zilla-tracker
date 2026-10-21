import Foundation
import Testing
import PhabricatorKit
@testable import Zilla

private let viewer = "PHID-USER-me"
private let reviewer = "PHID-USER-reviewer"
private let base: TimeInterval = 1_800_000_000

private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
}

private func makeRevision(id: Int = 1, author: String = viewer, modified: TimeInterval) throws -> Revision {
    let json = Data(#"""
    {
      "id": \#(id),
      "phid": "PHID-DREV-\#(id)",
      "fields": {
        "title": "Fix the thing",
        "authorPHID": "\#(author)",
        "status": {"value":"needs-review","name":"Needs Review","closed":false},
        "isDraft": false,
        "dateCreated": \#(Int(base)),
        "dateModified": \#(Int(base + modified))
      }
    }
    """#.utf8)
    return try decoder().decode(Revision.self, from: json)
}

private func makeTransaction(
    _ type: String,
    author: String,
    at offset: TimeInterval,
    comment: String? = nil,
    fields: String = "{}"
) throws -> RevisionTransaction {
    let comments = comment.map {
        #"[{"id":1,"phid":"PHID-XCMT-1","authorPHID":"\#(author)","dateCreated":\#(Int(base + offset)),"dateModified":\#(Int(base + offset)),"content":{"raw":"\#($0)"}}]"#
    } ?? "[]"
    let json = Data(#"""
    {
      "id": \#(Int(offset)),
      "phid": "PHID-XACT-\#(Int(offset))",
      "type": "\#(type)",
      "authorPHID": "\#(author)",
      "dateCreated": \#(Int(base + offset)),
      "dateModified": \#(Int(base + offset)),
      "comments": \#(comments),
      "fields": \#(fields)
    }
    """#.utf8)
    return try decoder().decode(RevisionTransaction.self, from: json)
}

private func at(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSince1970: base + offset)
}

@MainActor
struct RevisionActivityTests {
    @Test func separatesViewerActivityFromOthers() throws {
        let revision = try makeRevision(modified: 300)
        let activity = RevisionAttention.activity(
            of: revision,
            transactions: [
                try makeTransaction("update", author: viewer, at: 100),
                try makeTransaction("request-changes", author: reviewer, at: 200),
                try makeTransaction("comment", author: reviewer, at: 300, comment: "Please fix")
            ],
            viewerPHID: viewer
        )
        #expect(activity.latestFromViewer == at(100))
        #expect(activity.latestFromOthers == at(300))
        #expect(activity.dateModified == at(300))
    }

    @Test func ignoresApplicationAuthors() throws {
        let revision = try makeRevision(modified: 200)
        let activity = RevisionAttention.activity(
            of: revision,
            transactions: [
                try makeTransaction("reviewers", author: "PHID-APPS-PhabricatorHeraldApplication", at: 200)
            ],
            viewerPHID: viewer
        )
        #expect(activity.latestFromOthers == nil)
    }

    @Test func ignoresSubscriberChangesByOthers() throws {
        let revision = try makeRevision(modified: 200)
        let activity = RevisionAttention.activity(
            of: revision,
            transactions: [try makeTransaction("subscribers.add", author: reviewer, at: 200)],
            viewerPHID: viewer
        )
        #expect(activity.latestFromOthers == nil)
    }
}

@MainActor
struct RevisionNotifiableEventTests {
    private func notifiable(_ transactions: [RevisionTransaction]) throws -> RevisionEvent? {
        RevisionAttention.activity(
            of: try makeRevision(modified: 500),
            transactions: transactions,
            viewerPHID: viewer
        ).latestNotifiable
    }

    @Test func mapsTransactionsToEventKinds() throws {
        let cases: [(type: String, comment: String?, fields: String, kind: RevisionEventKind)] = [
            ("accept", nil, "{}", .accepted),
            ("request-changes", nil, "{}", .requestedChanges),
            ("reject", nil, "{}", .requestedChanges),
            ("resign", nil, "{}", .resigned),
            ("commandeer", nil, "{}", .commandeered),
            ("close", nil, "{}", .landed),
            ("abandon", nil, "{}", .abandoned),
            ("reclaim", nil, "{}", .reclaimed),
            ("reopen", nil, "{}", .reopened),
            ("status", nil, #"{"old":"needs-review","new":"accepted"}"#, .statusChanged("accepted")),
            ("comment", "Looks good", "{}", .commented),
            ("inline", "Nit", #"{"path":"a.swift","line":3}"#, .inlineCommented)
        ]
        for c in cases {
            let transaction = try makeTransaction(
                c.type, author: reviewer, at: 100, comment: c.comment, fields: c.fields
            )
            #expect(
                try notifiable([transaction]) == RevisionEvent(actorPHID: reviewer, kind: c.kind, date: at(100)),
                "\(c.type)"
            )
        }
    }

    @Test func excludesOtherTransactionKinds() throws {
        let excluded = [
            "reviewers", "update", "title", "summary", "test-plan", "bugzilla.bug-id",
            "subscribers.add", "projects.add", "core:columns", "harbormaster:buildable",
            "plan-changes", "request-review", "create", "mfa", "differential.unknown"
        ]
        for type in excluded {
            #expect(try notifiable([try makeTransaction(type, author: reviewer, at: 100)]) == nil, "\(type)")
        }
    }

    @Test func diffUpdateCountsForAttentionButDoesNotNotify() throws {
        let activity = RevisionAttention.activity(
            of: try makeRevision(modified: 100),
            transactions: [try makeTransaction("update", author: reviewer, at: 100)],
            viewerPHID: viewer
        )
        #expect(activity.latestFromOthers == at(100))
        #expect(activity.latestNotifiable == nil)
    }

    @Test func ignoresViewerAndNonUserAuthors() throws {
        let event = try notifiable([
            try makeTransaction("comment", author: reviewer, at: 100, comment: "Hi"),
            try makeTransaction("accept", author: viewer, at: 200),
            try makeTransaction("comment", author: "PHID-APPS-PhabricatorHeraldApplication", at: 300, comment: "Rule"),
            try makeTransaction("status", author: "PHID-APPS-PhabricatorDifferentialApplication", at: 400,
                                fields: #"{"old":"needs-review","new":"published"}"#)
        ])
        #expect(event == RevisionEvent(actorPHID: reviewer, kind: .commented, date: at(100)))
    }

    @Test func latestEventWins() throws {
        let other = "PHID-USER-other"
        let event = try notifiable([
            try makeTransaction("comment", author: other, at: 300, comment: "Later"),
            try makeTransaction("accept", author: reviewer, at: 100)
        ])
        #expect(event == RevisionEvent(actorPHID: other, kind: .commented, date: at(300)))
    }

    @Test func verdictWinsWithinOneEdit() throws {
        let edit = [
            try makeTransaction("comment", author: reviewer, at: 200, comment: "Ship it"),
            try makeTransaction("inline", author: reviewer, at: 200, comment: "Nit", fields: #"{"path":"a.swift","line":3}"#),
            try makeTransaction("accept", author: reviewer, at: 200)
        ]
        let expected = RevisionEvent(actorPHID: reviewer, kind: .accepted, date: at(200))
        #expect(try notifiable(edit) == expected)
        #expect(try notifiable(Array(edit.reversed())) == expected)
    }

    @Test func verbWinsOverDuplicateStatusChange() throws {
        let accept = [
            try makeTransaction("status", author: reviewer, at: 200, fields: #"{"old":"needs-review","new":"accepted"}"#),
            try makeTransaction("accept", author: reviewer, at: 200)
        ]
        #expect(try notifiable(accept)?.kind == .accepted)
        #expect(try notifiable(Array(accept.reversed()))?.kind == .accepted)

        let land = [
            try makeTransaction("close", author: reviewer, at: 200),
            try makeTransaction("status", author: reviewer, at: 200, fields: #"{"old":"accepted","new":"published"}"#)
        ]
        #expect(try notifiable(land)?.kind == .landed)
        #expect(try notifiable(Array(land.reversed()))?.kind == .landed)
    }

    @Test func statusChangeOutranksCommentsWithinOneEdit() throws {
        let edit = [
            try makeTransaction("comment", author: reviewer, at: 200, comment: "Done"),
            try makeTransaction("inline", author: reviewer, at: 200, comment: "Nit", fields: #"{"path":"a.swift","line":3}"#),
            try makeTransaction("status", author: reviewer, at: 200, fields: #"{"old":"accepted","new":"changes-planned"}"#)
        ]
        #expect(try notifiable(edit)?.kind == .statusChanged("changes-planned"))
        #expect(try notifiable(Array(edit.prefix(2).reversed()))?.kind == .inlineCommented)
    }
}

@MainActor
struct RevisionNotificationGatingTests {
    private let event = RevisionEvent(actorPHID: reviewer, kind: .accepted, date: at(200))

    private func activity(viewer viewerAt: TimeInterval? = nil, event: RevisionEvent?) -> RevisionActivity {
        RevisionActivity(
            dateModified: at(200),
            latestFromViewer: viewerAt.map(at),
            latestFromOthers: event?.date,
            latestNotifiable: event
        )
    }

    @Test func noActivityMeansNoEvent() {
        #expect(RevisionAttention.notifiableEvent(mark: nil, activity: nil) == nil)
        #expect(RevisionAttention.notifiableEvent(mark: nil, activity: activity(event: nil)) == nil)
    }

    @Test func unseenEventIsReturned() {
        #expect(RevisionAttention.notifiableEvent(mark: nil, activity: activity(event: event)) == event)
    }

    @Test func seenThroughGatesEvent() {
        let before = SeenMark(seenThrough: at(150), recordedAt: at(150))
        let exact = SeenMark(seenThrough: at(200), recordedAt: at(200))
        let after = SeenMark(seenThrough: at(250), recordedAt: at(250))
        #expect(RevisionAttention.notifiableEvent(mark: before, activity: activity(event: event)) == event)
        #expect(RevisionAttention.notifiableEvent(mark: exact, activity: activity(event: event)) == nil)
        #expect(RevisionAttention.notifiableEvent(mark: after, activity: activity(event: event)) == nil)
    }

    @Test func ownLaterActivityGatesEvent() {
        #expect(RevisionAttention.notifiableEvent(mark: nil, activity: activity(viewer: 100, event: event)) == event)
        #expect(RevisionAttention.notifiableEvent(mark: nil, activity: activity(viewer: 200, event: event)) == nil)
        #expect(RevisionAttention.notifiableEvent(mark: nil, activity: activity(viewer: 300, event: event)) == nil)
    }

    @Test func unviewedMarkDoesNotGate() {
        let unviewed = SeenMark(seenThrough: nil, recordedAt: at(300))
        #expect(RevisionAttention.notifiableEvent(mark: unviewed, activity: activity(event: event)) == event)
    }
}

@MainActor
struct RevisionAttentionTests {
    private func activity(viewer viewerAt: TimeInterval?, others othersAt: TimeInterval?) -> RevisionActivity {
        RevisionActivity(
            dateModified: at(max(viewerAt ?? 0, othersAt ?? 0)),
            latestFromViewer: viewerAt.map(at),
            latestFromOthers: othersAt.map(at)
        )
    }

    @Test func patchWithReviewAfterOwnUpdateNeedsAttention() {
        #expect(RevisionAttention.needsAttention(
            in: .patches, mark: nil, activity: activity(viewer: 100, others: 200)
        ))
    }

    @Test func patchUpdatedByAuthorAfterReviewDoesNot() {
        #expect(!RevisionAttention.needsAttention(
            in: .patches, mark: nil, activity: activity(viewer: 300, others: 200)
        ))
    }

    @Test func patchViewedAfterReviewDoesNot() {
        let mark = SeenMark(seenThrough: at(250), recordedAt: at(250))
        #expect(!RevisionAttention.needsAttention(
            in: .patches, mark: mark, activity: activity(viewer: 100, others: 200)
        ))
    }

    @Test func patchWithoutActivityFromOthersDoesNot() {
        #expect(!RevisionAttention.needsAttention(
            in: .patches, mark: nil, activity: activity(viewer: 100, others: nil)
        ))
        #expect(!RevisionAttention.needsAttention(in: .patches, mark: nil, activity: nil))
    }

    @Test func markedUnviewedNeedsAttentionInEitherList() {
        let mark = SeenMark(seenThrough: nil, recordedAt: at(0))
        #expect(RevisionAttention.needsAttention(in: .patches, mark: mark, activity: nil))
        #expect(RevisionAttention.needsAttention(in: .reviews, mark: mark, activity: nil))
    }

    @Test func unseenReviewNeedsAttention() {
        #expect(RevisionAttention.needsAttention(in: .reviews, mark: nil, activity: nil))
    }

    @Test func reviewUpdatedByAuthorSinceViewNeedsAttention() {
        let mark = SeenMark(seenThrough: at(100), recordedAt: at(100))
        #expect(RevisionAttention.needsAttention(
            in: .reviews, mark: mark, activity: activity(viewer: 50, others: 200)
        ))
    }

    @Test func activityIsFetchedOnlyWhenItCanChangeTheAnswer() throws {
        let revision = try makeRevision(modified: 200)
        let seenBefore = SeenMark(seenThrough: at(100), recordedAt: at(100))
        let seenAfter = SeenMark(seenThrough: at(300), recordedAt: at(300))
        let unviewed = SeenMark(seenThrough: nil, recordedAt: at(300))
        #expect(RevisionAttention.needsActivity(revision, in: .patches, mark: nil))
        #expect(!RevisionAttention.needsActivity(revision, in: .reviews, mark: nil))
        #expect(RevisionAttention.needsActivity(revision, in: .reviews, mark: seenBefore))
        #expect(!RevisionAttention.needsActivity(revision, in: .patches, mark: seenAfter))
        #expect(!RevisionAttention.needsActivity(revision, in: .patches, mark: unviewed))
    }
}
