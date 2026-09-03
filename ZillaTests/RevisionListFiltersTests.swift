import Foundation
import Testing
import PhabricatorKit
@testable import Zilla

private let viewerPHID = "PHID-USER-me"
private let groupA = "PHID-PROJ-aaa"
private let groupB = "PHID-PROJ-bbb"
private let ownerPackage = "PHID-OPKG-zzz"
private let viewerProjects: Set<String> = [groupA, groupB]

private func makeRevision(
    id: Int,
    title: String = "Fix the thing",
    authorPHID: String = "PHID-USER-other",
    bugID: String? = nil,
    reviewerPHIDs: [String]
) throws -> Revision {
    let reviewers = reviewerPHIDs
        .map { #"{"reviewerPHID":"\#($0)","status":"added","isBlocking":false}"# }
        .joined(separator: ",")
    let bug = bugID.map { #""bugzilla.bug-id":"\#($0)","# } ?? ""
    let json = Data(#"""
    {
      "id": \#(id),
      "phid": "PHID-DREV-\#(id)",
      "fields": {
        "title": "\#(title)",
        "authorPHID": "\#(authorPHID)",
        "status": {"value":"needs-review","name":"Needs Review","closed":false},
        "isDraft": false,
        "dateCreated": 1700000000,
        "dateModified": 1700000000,
        \#(bug)
        "diffPHID": "PHID-DIFF-1"
      },
      "attachments": { "reviewers": { "reviewers": [\#(reviewers)] } }
    }
    """#.utf8)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(Revision.self, from: json)
}

struct ReviewerScopeTests {
    @Test func directReviewerResolvesToDirectScope() throws {
        let revision = try makeRevision(id: 1, reviewerPHIDs: [viewerPHID])
        let scopes = ReviewerScope.scopes(
            for: revision, viewerPHID: viewerPHID, viewerProjectPHIDs: viewerProjects
        )
        #expect(scopes == [.direct])
    }

    @Test func projectReviewerResolvesToThatProject() throws {
        let revision = try makeRevision(id: 2, reviewerPHIDs: [groupA, "PHID-USER-someone"])
        let scopes = ReviewerScope.scopes(
            for: revision, viewerPHID: viewerPHID, viewerProjectPHIDs: viewerProjects
        )
        #expect(scopes == [.project(groupA)])
    }

    @Test func bothDirectAndProjectReviewersResolveToBothScopes() throws {
        let revision = try makeRevision(id: 3, reviewerPHIDs: [viewerPHID, groupB])
        let scopes = ReviewerScope.scopes(
            for: revision, viewerPHID: viewerPHID, viewerProjectPHIDs: viewerProjects
        )
        #expect(scopes == [.direct, .project(groupB)])
    }

    @Test func ownerPackageReviewerFallsBackToOther() throws {
        let revision = try makeRevision(id: 4, reviewerPHIDs: [ownerPackage])
        let scopes = ReviewerScope.scopes(
            for: revision, viewerPHID: viewerPHID, viewerProjectPHIDs: viewerProjects
        )
        #expect(scopes == [.other])
    }

    @Test func presentOrdersDirectFirstThenProjectsByNameThenOther() throws {
        let revisions = [
            try makeRevision(id: 5, reviewerPHIDs: [ownerPackage]),
            try makeRevision(id: 6, reviewerPHIDs: [groupB]),
            try makeRevision(id: 7, reviewerPHIDs: [groupA]),
            try makeRevision(id: 8, reviewerPHIDs: [viewerPHID])
        ]
        let names = [groupA: "Zebra Reviewers", groupB: "Alpha Reviewers"]
        let entries = ReviewerScope.present(
            in: revisions,
            viewerPHID: viewerPHID,
            viewerProjectPHIDs: viewerProjects,
            name: { names[$0] }
        )
        #expect(entries.map(\.title) == ["Assigned to Me", "Alpha Reviewers", "Zebra Reviewers", "Other"])
        #expect(entries.map(\.scope) == [.direct, .project(groupB), .project(groupA), .other])
    }

    @Test func presentFallsBackToPHIDWhenNameIsUnknown() throws {
        let revisions = [try makeRevision(id: 9, reviewerPHIDs: [groupA])]
        let entries = ReviewerScope.present(
            in: revisions,
            viewerPHID: viewerPHID,
            viewerProjectPHIDs: viewerProjects,
            name: { _ in nil }
        )
        #expect(entries.map(\.title) == [groupA])
    }
}

struct RevisionSearchMatchingTests {
    @Test func blankSearchMatchesEverything() throws {
        let revision = try makeRevision(id: 10, reviewerPHIDs: [viewerPHID])
        #expect(revisionMatches(revision, search: "   "))
    }

    @Test func matchesTitleCaseAndDiacriticInsensitively() throws {
        let revision = try makeRevision(id: 11, title: "Résumé parsing", reviewerPHIDs: [viewerPHID])
        #expect(revisionMatches(revision, search: "resume"))
        #expect(revisionMatches(revision, search: "PARSING"))
        #expect(!revisionMatches(revision, search: "unrelated"))
    }

    @Test func matchesRevisionLabelAndBareID() throws {
        let revision = try makeRevision(id: 12345, reviewerPHIDs: [viewerPHID])
        #expect(revisionMatches(revision, search: "D12345"))
        #expect(revisionMatches(revision, search: "d12345"))
        #expect(revisionMatches(revision, search: "12345"))
    }

    @Test func matchesLinkedBugNumber() throws {
        let revision = try makeRevision(id: 13, bugID: "1899000", reviewerPHIDs: [viewerPHID])
        #expect(revisionMatches(revision, search: "1899000"))
        #expect(!revisionMatches(revision, search: "1899001"))
    }
}

struct RevisionListDefaultsTests {
    @Test func listsAndScopesCarryStableRawValues() {
        #expect(RevisionList.allCases.map(\.rawValue) == ["reviews", "patches"])
        #expect(PatchScope.allCases.map(\.rawValue) == ["active", "landed"])
        #expect(RevisionList.reviews.title == "Reviews")
        #expect(RevisionList.patches.title == "Patches")
    }
}
