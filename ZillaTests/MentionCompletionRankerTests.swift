import Foundation
import Testing
@testable import Zilla
import BugzillaKit
import PhabricatorKit

struct MentionCompletionRankerTests {
    @Test func prefixMatchRanksAheadOfOtherMatches() {
        let items = [
            MentionCompletionItem(source: .bugzilla, handle: "other", displayName: "Other Fcha", detail: "other@example.com"),
            MentionCompletionItem(source: .bugzilla, handle: "fchasen", displayName: "Fred Chasen", detail: "fchasen@example.com")
        ]

        let ranked = MentionCompletionRanker.ranked(items, query: "fcha")

        #expect(ranked.first?.handle == "fchasen")
    }

    @Test func bugzillaUserCompletionInsertsPlainHandleWithoutTrigger() {
        let user = User(id: 1, name: "fred@example.com", realName: "Fred Chasen", nick: "fchasen")
        let item = MentionCompletionItem(user: user)

        #expect(item.replacementText == "fchasen ")
        #expect(!item.replacementText.contains("@"))
        #expect(item.avatarEmail == "fred@example.com")
    }

    @Test func emptyQueryKeepsDefaultOrder() {
        let items = [
            MentionCompletionItem(source: .bugzilla, handle: "zlast", displayName: "Last", detail: "zlast@example.com"),
            MentionCompletionItem(source: .bugzilla, handle: "afirst", displayName: "First", detail: "afirst@example.com")
        ]

        let ranked = MentionCompletionRanker.ranked(items, query: "")

        #expect(ranked.map(\.handle) == ["zlast", "afirst"])
    }

    @Test func bugzillaDefaultsUseLastCommentersThenReporter() {
        let now = Date()
        let bug = Bug(
            id: 1,
            summary: "Test",
            status: "NEW",
            resolution: "",
            product: "Core",
            component: "DOM",
            reporter: "reporter@example.com"
        )
        let comments = [
            Comment(id: 1, bugId: 1, creator: "old@example.com", text: "old", creationTime: now.addingTimeInterval(-60), isPrivate: false, count: 1),
            Comment(id: 2, bugId: 1, creator: "last@example.com", text: "last", creationTime: now, isPrivate: false, count: 2)
        ]

        let context = MentionCompletionContext.bugzilla(bug: bug, comments: comments)

        #expect(context.source == .bugzilla)
        #expect(context.defaultItems.map(\.handle) == ["last", "old", "reporter"])
    }

    @Test func bugzillaDefaultsFallBackToReporterWithoutComments() {
        let bug = Bug(
            id: 1,
            summary: "Test",
            status: "NEW",
            resolution: "",
            product: "Core",
            component: "DOM",
            reporter: "reporter@example.com"
        )

        let context = MentionCompletionContext.bugzilla(bug: bug, comments: [])

        #expect(context.defaultItems.map(\.handle) == ["reporter"])
    }

    @Test func phabricatorDefaultsFallBackToAuthorWithoutComments() throws {
        let revision = try makeRevision(authorPHID: "PHID-USER-author")
        let author = try makePhabricatorUser(
            phid: "PHID-USER-author",
            userName: "author",
            realName: "Revision Author",
            primaryEmail: "author@example.com"
        )

        let context = MentionCompletionContext.phabricator(
            revision: revision,
            transactions: [],
            inlines: [],
            userDirectory: [author.phid: author]
        )

        #expect(context.defaultItems.map(\.handle) == ["author"])
    }

    @Test func currentBugzillaUserIsExcludedFromResults() {
        let currentUser = User(id: 1, name: "fchasen@example.com", realName: "Fred Chasen", nick: "fchasen")
        let items = [
            MentionCompletionItem(source: .bugzilla, handle: "fchasen", displayName: "Fred Chasen", detail: "fchasen@example.com"),
            MentionCompletionItem(source: .bugzilla, handle: "reviewer", displayName: "Reviewer", detail: "reviewer@example.com")
        ]

        let filtered = MentionCompletionRanker.excludingCurrentUser(
            items,
            bugzillaUser: currentUser,
            phabricatorUser: nil
        )

        #expect(filtered.map(\.handle) == ["reviewer"])
    }

    @Test func currentPhabricatorUserIsExcludedFromResults() throws {
        let currentUser = try makePhabricatorUser(
            phid: "PHID-USER-current",
            userName: "fchasen",
            realName: "Fred Chasen",
            primaryEmail: "fchasen@example.com"
        )
        let items = [
            MentionCompletionItem(user: currentUser),
            MentionCompletionItem(source: .phabricator, handle: "reviewer", displayName: "Reviewer", detail: "reviewer@example.com")
        ]

        let filtered = MentionCompletionRanker.excludingCurrentUser(
            items,
            bugzillaUser: nil,
            phabricatorUser: currentUser
        )

        #expect(filtered.map(\.handle) == ["reviewer"])
    }

    private func makePhabricatorUser(
        phid: String,
        userName: String,
        realName: String,
        primaryEmail: String
    ) throws -> PhabricatorUser {
        let data = """
        {
            "phid": "\(phid)",
            "userName": "\(userName)",
            "realName": "\(realName)",
            "primaryEmail": "\(primaryEmail)",
            "image": "https://example.com/avatar.png"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PhabricatorUser.self, from: data)
    }

    private func makeRevision(authorPHID: String) throws -> Revision {
        let data = """
        {
            "id": 123,
            "phid": "PHID-DREV-test",
            "fields": {
                "title": "Test",
                "uri": "https://phabricator.example.com/D123",
                "authorPHID": "\(authorPHID)",
                "status": {
                    "value": "needs-review",
                    "name": "Needs Review",
                    "closed": false
                },
                "summary": "",
                "testPlan": "",
                "isDraft": false,
                "dateCreated": 1,
                "dateModified": 2
            },
            "attachments": {}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Revision.self, from: data)
    }
}
