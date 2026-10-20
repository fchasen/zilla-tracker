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
    comment: String? = nil
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
      "fields": {}
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
