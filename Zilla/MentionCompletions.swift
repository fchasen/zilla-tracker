import Foundation
import BugzillaKit
import PhabricatorKit

struct MentionCompletionItem: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case bugzilla
        case phabricator
    }

    let source: Source
    let handle: String
    let displayName: String
    let detail: String
    let avatarEmail: String?
    let avatarURL: URL?

    var id: String { "\(source.rawValue):\(detail):\(handle)" }
    var replacementText: String { "\(handle) " }

    init(
        source: Source,
        handle: String,
        displayName: String,
        detail: String,
        avatarEmail: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.source = source
        self.handle = handle
        self.displayName = displayName
        self.detail = detail
        self.avatarEmail = avatarEmail
        self.avatarURL = avatarURL
    }

    init(user: User) {
        let handle: String = {
            if let nick = user.nick?.trimmingCharacters(in: .whitespacesAndNewlines), !nick.isEmpty {
                return nick
            }
            return User.localPart(of: user.name)
        }()
        let display = user.realName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            source: .bugzilla,
            handle: handle,
            displayName: display?.isEmpty == false ? display! : user.displayName,
            detail: user.name,
            avatarEmail: user.email ?? user.name
        )
    }

    init(user: PhabricatorUser) {
        let display = user.realName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            source: .phabricator,
            handle: user.userName,
            displayName: display?.isEmpty == false ? display! : user.userName,
            detail: user.primaryEmail ?? user.userName,
            avatarEmail: user.primaryEmail,
            avatarURL: user.image
        )
    }

    static func bugzilla(email: String, displayName: String? = nil) -> MentionCompletionItem {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MentionCompletionItem(
            source: .bugzilla,
            handle: User.localPart(of: clean),
            displayName: display?.isEmpty == false ? display! : User.displayName(for: clean),
            detail: clean,
            avatarEmail: clean
        )
    }
}

struct MentionCompletionContext: Equatable, Sendable {
    var source: MentionCompletionItem.Source?
    var defaultItems: [MentionCompletionItem]

    static let none = MentionCompletionContext(source: nil, defaultItems: [])

    static func bugzilla(bug: Bug?, comments: [Comment]) -> MentionCompletionContext {
        var items: [MentionCompletionItem] = []
        for comment in comments.sorted(by: { $0.creationTime > $1.creationTime }) {
            appendBugzilla(email: comment.creator, detail: nil, to: &items)
        }
        if let bug {
            appendBugzilla(email: bug.reporter ?? bug.creator, detail: bug.creatorDetail, to: &items)
        }
        return MentionCompletionContext(source: .bugzilla, defaultItems: MentionCompletionRanker.unique(items))
    }

    static func phabricator(
        revision: Revision?,
        transactions: [RevisionTransaction],
        inlines: [InlineComment],
        userDirectory: [String: PhabricatorUser]
    ) -> MentionCompletionContext {
        var phids: [(Date, String)] = []
        for transaction in transactions {
            for comment in transaction.comments where comment.removed != true {
                guard let raw = comment.content.raw,
                      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if let phid = comment.authorPHID ?? transaction.authorPHID {
                    phids.append((comment.dateCreated, phid))
                }
            }
        }
        for inline in inlines where !inline.isDeleted {
            if let phid = inline.authorPHID {
                phids.append((inline.dateModified ?? inline.dateCreated ?? .distantPast, phid))
            }
        }

        var items: [MentionCompletionItem] = phids
            .sorted { $0.0 > $1.0 }
            .compactMap { userDirectory[$0.1].map(MentionCompletionItem.init(user:)) }

        if let authorPHID = revision?.fields.authorPHID,
           let author = userDirectory[authorPHID] {
            items.append(MentionCompletionItem(user: author))
        }

        return MentionCompletionContext(source: .phabricator, defaultItems: MentionCompletionRanker.unique(items))
    }

    private static func appendBugzilla(email: String?, detail: User?, to items: inout [MentionCompletionItem]) {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return }
        if let detail, matches(detail, email: email) {
            items.append(MentionCompletionItem(user: detail))
        } else {
            items.append(.bugzilla(email: email))
        }
    }

    private static func matches(_ user: User, email: String) -> Bool {
        user.name.caseInsensitiveCompare(email) == .orderedSame
            || user.email?.caseInsensitiveCompare(email) == .orderedSame
    }
}

extension Workspace {
    var revisionMentionCompletionContext: MentionCompletionContext {
        MentionCompletionContext.phabricator(
            revision: loadedRevision,
            transactions: loadedRevisionTransactions,
            inlines: loadedRevisionInlines,
            userDirectory: revisionUserDirectory
        )
    }
}

enum MentionCompletionRanker {
    static func excludingCurrentUser(
        _ items: [MentionCompletionItem],
        bugzillaUser: User?,
        phabricatorUser: PhabricatorUser?
    ) -> [MentionCompletionItem] {
        items.filter { item in
            switch item.source {
            case .bugzilla:
                guard let bugzillaUser else { return true }
                return !item.matches(bugzillaUser: bugzillaUser)
            case .phabricator:
                guard let phabricatorUser else { return true }
                return !item.matches(phabricatorUser: phabricatorUser)
            }
        }
    }

    static func unique(_ items: [MentionCompletionItem]) -> [MentionCompletionItem] {
        var seen: Set<String> = []
        var result: [MentionCompletionItem] = []
        result.reserveCapacity(items.count)
        for item in items {
            let key = "\(item.source.rawValue):\(item.handle.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(item)
        }
        return result
    }

    static func ranked(
        _ items: [MentionCompletionItem],
        query: String,
        limit: Int = 8
    ) -> [MentionCompletionItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return Array(unique(items).prefix(limit))
        }
        let scored = items.compactMap { item -> (MentionCompletionItem, Int)? in
            guard let score = score(item, query: normalizedQuery) else { return nil }
            return (item, score)
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.handle.localizedCaseInsensitiveCompare(rhs.0.handle) != .orderedSame {
                return lhs.0.handle.localizedCaseInsensitiveCompare(rhs.0.handle) == .orderedAscending
            }
            return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
        }
        var seen: Set<String> = []
        var ranked: [MentionCompletionItem] = []
        ranked.reserveCapacity(min(limit, sorted.count))
        for (item, _) in sorted {
            let key = item.handle.lowercased()
            guard seen.insert(key).inserted else { continue }
            ranked.append(item)
            if ranked.count == limit { break }
        }
        return ranked
    }

    static func score(_ item: MentionCompletionItem, query: String) -> Int? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return 0
        }
        let handle = item.handle.lowercased()
        let display = item.displayName.lowercased()
        let detail = item.detail.lowercased()
        if handle == normalizedQuery { return 0 }
        if handle.hasPrefix(normalizedQuery) { return 10 }
        if display.hasPrefix(normalizedQuery) { return 20 }
        if detail.hasPrefix(normalizedQuery) { return 30 }
        if handle.contains(normalizedQuery) { return 40 }
        if display.contains(normalizedQuery) { return 50 }
        if detail.contains(normalizedQuery) { return 60 }
        return nil
    }
}

private extension MentionCompletionItem {
    func matches(bugzillaUser: User) -> Bool {
        matchesAny([
            bugzillaUser.name,
            bugzillaUser.email,
            bugzillaUser.nick,
            User.localPart(of: bugzillaUser.name)
        ])
    }

    func matches(phabricatorUser: PhabricatorUser) -> Bool {
        matchesAny([
            phabricatorUser.userName,
            phabricatorUser.primaryEmail
        ])
    }

    func matchesAny(_ values: [String?]) -> Bool {
        values.contains { raw in
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return false
            }
            return handle.caseInsensitiveCompare(value) == .orderedSame
                || detail.caseInsensitiveCompare(value) == .orderedSame
        }
    }
}
