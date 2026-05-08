//
//  ResourceCache.swift
//  Zilla
//

import Foundation
import BugzillaKit
import PhabricatorKit

enum CacheKey: Hashable, Sendable {
    case whoami
    case selectableProducts
    case bug(Bug.ID)
    case comments(bugID: Bug.ID)
    case bugSearch(BugQuery)
    case bugCount(BugQuery)
    case dependencyMeta(Bug.ID)
    case phabUser
    case revisionSearch(RevisionQuery)
    case revision(Int)
    case revisionDiff(Int)
    case revisionTransactions(Int)
    case revisionStack(Int)
    case phabricatorUser(String)
    case fileContent(repositoryPHID: String, commit: String, path: String)
}

enum CacheRetentionGroup: Hashable {
    case comments
    case revisionDiff
    case revisionTransactions
    case fileContent
}

extension CacheKey {
    var retentionGroup: CacheRetentionGroup? {
        switch self {
        case .comments:
            return .comments
        case .revisionDiff:
            return .revisionDiff
        case .revisionTransactions:
            return .revisionTransactions
        case .fileContent:
            return .fileContent
        case .whoami, .selectableProducts, .bug, .bugSearch, .bugCount,
             .dependencyMeta, .phabUser, .revisionSearch, .revision,
             .revisionStack, .phabricatorUser:
            return nil
        }
    }

    var freshTTL: TimeInterval {
        switch self {
        // User identity rarely changes within a session.
        case .whoami, .phabUser, .selectableProducts, .phabricatorUser:
            return 6 * 60 * 60
        // Revision detail (header/transactions/diff/stack) — keep cached longer
        // so flipping between recently-opened revisions is instant.
        case .revision, .revisionDiff, .revisionTransactions, .revisionStack:
            return 5 * 60
        // Bug / list searches — tighter freshness because list contents
        // change as the user works elsewhere.
        case .bug, .comments, .bugSearch, .bugCount, .revisionSearch:
            return 60
        case .dependencyMeta:
            return 24 * 60 * 60
        case .fileContent:
            return 24 * 60 * 60
        }
    }

    var hardTTL: TimeInterval {
        switch self {
        case .whoami, .phabUser, .selectableProducts, .phabricatorUser:
            return 7 * 24 * 60 * 60
        case .revision, .revisionDiff, .revisionTransactions, .revisionStack:
            return 60 * 60
        case .bug, .comments, .bugSearch, .bugCount, .revisionSearch:
            return 10 * 60
        case .dependencyMeta:
            return 7 * 24 * 60 * 60
        case .fileContent:
            return 7 * 24 * 60 * 60
        }
    }
}

enum CacheError: Error {
    case typeMismatch
}

@MainActor
@Observable
final class ResourceCache {
    private struct Entry {
        let value: Any
        let storedAt: Date
        var lastAccessed: Date
    }

    enum Freshness {
        case missing, fresh, stale, expired
    }

    private(set) var version: UInt64 = 0
    private var entries: [CacheKey: Entry] = [:]
    private var inflight: [CacheKey: Task<Any, Error>] = [:]
    private var inflightToken: [CacheKey: UUID] = [:]
    private var revalidationListeners: [CacheKey: Task<Void, Never>] = [:]
    private let maxEntryCount: Int
    private let groupLimits: [CacheRetentionGroup: Int]

    init(
        maxEntryCount: Int = 120,
        groupLimits: [CacheRetentionGroup: Int]? = nil
    ) {
        self.maxEntryCount = max(1, maxEntryCount)
        self.groupLimits = (groupLimits ?? [
            .comments: 20,
            .revisionDiff: 4,
            .revisionTransactions: 8,
            .fileContent: 16
        ]).mapValues { max(0, $0) }
    }

    func freshness(for key: CacheKey, now: Date = .now) -> Freshness {
        guard let entry = entries[key] else { return .missing }
        let age = now.timeIntervalSince(entry.storedAt)
        if age < key.freshTTL { return .fresh }
        if age < key.hardTTL { return .stale }
        return .expired
    }

    func get<V>(_ key: CacheKey, as: V.Type = V.self) -> V? {
        guard var entry = entries[key],
              let value = entry.value as? V else { return nil }
        entry.lastAccessed = .now
        entries[key] = entry
        return value
    }

    func storedAt(_ key: CacheKey) -> Date? {
        entries[key]?.storedAt
    }

    func store<V>(_ value: V, for key: CacheKey, storedAt: Date = .now) {
        entries[key] = Entry(value: value, storedAt: storedAt, lastAccessed: storedAt)
        _ = trim(now: storedAt)
        version &+= 1
    }

    func invalidate(_ key: CacheKey) {
        cancelInflight(for: key)
        if entries.removeValue(forKey: key) != nil {
            version &+= 1
        }
    }

    func invalidateBug(id: Bug.ID) {
        var changed = false
        for key in [CacheKey.bug(id), .comments(bugID: id), .dependencyMeta(id)] {
            cancelInflight(for: key)
            if entries.removeValue(forKey: key) != nil { changed = true }
        }
        if changed { version &+= 1 }
    }

    func invalidateRevision(id: Int) {
        var changed = false
        for key in [
            CacheKey.revision(id),
            .revisionDiff(id),
            .revisionTransactions(id),
            .revisionStack(id)
        ] {
            cancelInflight(for: key)
            if entries.removeValue(forKey: key) != nil { changed = true }
        }
        if changed { version &+= 1 }
    }

    func clear() {
        for (_, task) in inflight { task.cancel() }
        for (_, listener) in revalidationListeners { listener.cancel() }
        inflight.removeAll()
        inflightToken.removeAll()
        revalidationListeners.removeAll()
        if !entries.isEmpty {
            entries.removeAll()
            version &+= 1
        }
    }

    private func cancelInflight(for key: CacheKey) {
        if let task = inflight.removeValue(forKey: key) {
            task.cancel()
        }
        inflightToken.removeValue(forKey: key)
        if let listener = revalidationListeners.removeValue(forKey: key) {
            listener.cancel()
        }
    }

    @discardableResult
    private func trim(now: Date = .now) -> Bool {
        var changed = removeExpiredEntries(now: now)
        for (group, limit) in groupLimits {
            let groupKeys = entries.keys.filter { $0.retentionGroup == group }
            changed = removeLeastRecentlyAccessed(from: groupKeys, keeping: limit) || changed
        }
        changed = removeLeastRecentlyAccessed(from: Array(entries.keys), keeping: maxEntryCount) || changed
        return changed
    }

    @discardableResult
    private func removeExpiredEntries(now: Date) -> Bool {
        let expired = entries.compactMap { key, entry -> CacheKey? in
            now.timeIntervalSince(entry.storedAt) >= key.hardTTL ? key : nil
        }
        for key in expired {
            entries.removeValue(forKey: key)
        }
        return !expired.isEmpty
    }

    @discardableResult
    private func removeLeastRecentlyAccessed(from keys: [CacheKey], keeping limit: Int) -> Bool {
        guard keys.count > limit else { return false }
        let overflow = keys.count - limit
        let orderedKeys = keys
            .compactMap { key -> (CacheKey, Date)? in
                entries[key].map { (key, $0.lastAccessed) }
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return String(describing: lhs.0) < String(describing: rhs.0)
                }
                return lhs.1 < rhs.1
            }
            .prefix(overflow)
            .map(\.0)
        for key in orderedKeys {
            entries.removeValue(forKey: key)
        }
        return !orderedKeys.isEmpty
    }
}

extension ResourceCache {
    func fetch<V>(
        key: CacheKey,
        force: Bool,
        onRefresh: ((V) -> Void)? = nil,
        provider: @escaping () async throws -> V
    ) async throws -> V {
        if !force {
            switch freshness(for: key) {
            case .fresh:
                if let cached: V = get(key) { return cached }
            case .stale:
                if let cached: V = get(key) {
                    kickRevalidation(key: key, provider: provider, onRefresh: onRefresh)
                    return cached
                }
            case .expired, .missing:
                break
            }
        }

        let task = startOrJoin(key: key, provider: provider)
        let any = try await task.value
        guard let typed = any as? V else { throw CacheError.typeMismatch }
        return typed
    }

    private func startOrJoin<V>(
        key: CacheKey,
        provider: @escaping () async throws -> V
    ) -> Task<Any, Error> {
        if let existing = inflight[key] { return existing }

        let token = UUID()
        inflightToken[key] = token

        let task = Task<Any, Error> { @MainActor [weak self] in
            do {
                let value = try await provider()
                if let self, self.inflightToken[key] == token {
                    self.store(value, for: key)
                    self.inflight.removeValue(forKey: key)
                    self.inflightToken.removeValue(forKey: key)
                }
                return value as Any
            } catch {
                if let self, self.inflightToken[key] == token {
                    self.inflight.removeValue(forKey: key)
                    self.inflightToken.removeValue(forKey: key)
                }
                throw error
            }
        }
        inflight[key] = task
        return task
    }

    private func kickRevalidation<V>(
        key: CacheKey,
        provider: @escaping () async throws -> V,
        onRefresh: ((V) -> Void)?
    ) {
        let task = startOrJoin(key: key, provider: provider)
        guard let onRefresh else { return }
        revalidationListeners[key]?.cancel()
        let listener = Task { @MainActor [weak self] in
            defer { self?.revalidationListeners[key] = nil }
            if let any = try? await task.value,
               let typed = any as? V,
               !Task.isCancelled {
                onRefresh(typed)
            }
        }
        revalidationListeners[key] = listener
    }
}

extension ResourceCache {
    func bug(
        id: Bug.ID,
        force: Bool = false,
        using client: BugzillaClient,
        onRefresh: ((Bug) -> Void)? = nil
    ) async throws -> Bug {
        try await fetch(key: .bug(id), force: force, onRefresh: onRefresh) {
            try await client.getBug(id: id)
        }
    }

    func comments(
        bugID: Bug.ID,
        force: Bool = false,
        using client: BugzillaClient,
        onRefresh: (([Comment]) -> Void)? = nil
    ) async throws -> [Comment] {
        try await fetch(key: .comments(bugID: bugID), force: force, onRefresh: onRefresh) {
            try await client.comments(bugID: bugID)
        }
    }

    func bugList(
        _ query: BugQuery,
        force: Bool = false,
        using client: BugzillaClient,
        onRefresh: ((BugSearchResult) -> Void)? = nil
    ) async throws -> BugSearchResult {
        try await fetch(key: .bugSearch(query), force: force, onRefresh: onRefresh) {
            try await client.searchBugs(query)
        }
    }

    func bugCount(
        _ query: BugQuery,
        force: Bool = false,
        using client: BugzillaClient,
        onRefresh: ((Int) -> Void)? = nil
    ) async throws -> Int {
        try await fetch(key: .bugCount(query), force: force, onRefresh: onRefresh) {
            try await client.countBugs(query)
        }
    }

    func selectableProducts(
        force: Bool = false,
        using client: BugzillaClient
    ) async throws -> [Product] {
        try await fetch(key: .selectableProducts, force: force) {
            try await client.selectableProducts()
        }
    }

    func revisionSearch(
        _ query: RevisionQuery,
        force: Bool = false,
        using client: PhabricatorClient,
        onRefresh: ((RevisionSearchResult) -> Void)? = nil
    ) async throws -> RevisionSearchResult {
        try await fetch(key: .revisionSearch(query), force: force, onRefresh: onRefresh) {
            try await client.searchRevisions(query)
        }
    }

    func whoami(force: Bool = false, using client: BugzillaClient) async throws -> User {
        try await fetch(key: .whoami, force: force) {
            try await client.whoami()
        }
    }

    func phabUser(force: Bool = false, using client: PhabricatorClient) async throws -> PhabricatorUser {
        try await fetch(key: .phabUser, force: force) {
            try await client.whoami()
        }
    }

    func revision(
        id: Int,
        force: Bool = false,
        using client: PhabricatorClient,
        onRefresh: ((Revision) -> Void)? = nil
    ) async throws -> Revision {
        try await fetch(key: .revision(id), force: force, onRefresh: onRefresh) {
            let query = RevisionQuery(
                constraints: RevisionQuery.Constraints(ids: [id]),
                attachments: RevisionQuery.Attachments(
                    reviewers: true,
                    reviewersExtra: true,
                    subscribers: true,
                    projects: true
                )
            )
            let result = try await client.searchRevisions(query)
            guard let revision = result.data.first else {
                throw PhabricatorError.invalidResponse
            }
            return revision
        }
    }

    func revisionLatestDiff(
        revisionPHID: String,
        revisionID: Int,
        force: Bool = false,
        using client: PhabricatorClient,
        onRefresh: ((DiffDetail?) -> Void)? = nil
    ) async throws -> DiffDetail? {
        try await fetch(key: .revisionDiff(revisionID), force: force, onRefresh: onRefresh) {
            let diffs = try await client.searchDiffs(.forRevision(revisionPHID))
            guard let latest = diffs.data.first else { return nil }
            let details = try await client.getDiffs(ids: [latest.id])
            guard let detail = details.first else { return nil }
            return detail.merging(searchMetadata: latest)
        }
    }

    func revisionTransactions(
        id: Int,
        revisionPHID: String,
        force: Bool = false,
        using client: PhabricatorClient,
        onRefresh: (([RevisionTransaction]) -> Void)? = nil
    ) async throws -> [RevisionTransaction] {
        try await fetch(key: .revisionTransactions(id), force: force, onRefresh: onRefresh) {
            let result = try await client.searchTransactions(
                TransactionQuery(objectIdentifier: revisionPHID, limit: 100)
            )
            return result.data
        }
    }

    func resolveUsers(
        phids: [String],
        using client: PhabricatorClient
    ) async -> [String: PhabricatorUser] {
        let unique = Array(Set(phids))
        var resolved: [String: PhabricatorUser] = [:]
        var missing: [String] = []
        for phid in unique {
            if let cached: PhabricatorUser = get(.phabricatorUser(phid)) {
                resolved[phid] = cached
            } else {
                missing.append(phid)
            }
        }
        if !missing.isEmpty,
           let users = try? await client.searchUsers(phids: missing) {
            for user in users {
                store(user, for: .phabricatorUser(user.phid))
                resolved[user.phid] = user
            }
        }
        return resolved
    }

    func fileContent(
        repositoryPHID: String,
        commit: String,
        path: String,
        force: Bool = false,
        using client: PhabricatorClient
    ) async throws -> String? {
        let key = CacheKey.fileContent(repositoryPHID: repositoryPHID, commit: commit, path: path)
        return try await fetch(key: key, force: force) {
            try await client.getFileContent(repositoryPHID: repositoryPHID, commit: commit, path: path)
        }
    }
}

extension ResourceCache {
    func dependencyMeta(for id: Bug.ID) -> DependencyMetadata? {
        get(.dependencyMeta(id))
    }

    func loadDependencyMeta(ids: [Bug.ID], using client: BugzillaClient) async {
        let needed = ids.filter {
            switch freshness(for: .dependencyMeta($0)) {
            case .missing, .expired: return true
            case .fresh, .stale: return false
            }
        }
        guard !needed.isEmpty else { return }
        guard let bugs = try? await client.getBugs(ids: needed) else { return }
        for bug in bugs {
            let assigneeDisplay: String? = {
                if let detail = bug.assignedToDetail {
                    if let real = detail.realName, !real.isEmpty { return real }
                    return detail.name
                }
                return bug.assignedTo
            }()
            let meta = DependencyMetadata(
                id: bug.id,
                summary: bug.summary,
                status: bug.status,
                resolution: bug.resolution,
                type: bug.type,
                assigneeDisplayName: assigneeDisplay
            )
            store(meta, for: .dependencyMeta(bug.id))
        }
    }
}

struct RevisionStackGraph: Sendable, Equatable {
    struct Node: Sendable, Equatable {
        let id: Int
        let phid: String
        let title: String
        let status: RevisionStatus
        let authorPHID: String
    }

    var ordered: [Node]
    var focalID: Int
    var truncatedAtBranch: Bool

    var focalNode: Node? {
        ordered.first { $0.id == focalID }
    }
}

extension ResourceCache {
    func revisionStack(
        revisionID: Int,
        revisionPHID: String,
        force: Bool = false,
        using client: PhabricatorClient,
        onRefresh: ((RevisionStackGraph) -> Void)? = nil
    ) async throws -> RevisionStackGraph {
        try await fetch(key: .revisionStack(revisionID), force: force, onRefresh: onRefresh) { [weak self] in
            try await Self.computeRevisionStack(
                focalID: revisionID,
                focalPHID: revisionPHID,
                client: client,
                cache: self
            )
        }
    }

    @MainActor
    private static func computeRevisionStack(
        focalID: Int,
        focalPHID: String,
        client: PhabricatorClient,
        cache: ResourceCache?
    ) async throws -> RevisionStackGraph {
        let maxDepth = 32

        var ancestorChain: [String] = []
        var truncated = false
        var visited: Set<String> = [focalPHID]
        var cursor = focalPHID
        for _ in 0..<maxDepth {
            let edges = try await client.searchEdges(
                EdgeQuery(sourcePHIDs: [cursor], types: [.parentsOfSource])
            ).data
            if edges.isEmpty { break }
            if edges.count > 1 { truncated = true }
            let nextPHID = edges[0].destinationPHID
            if visited.contains(nextPHID) { break }
            visited.insert(nextPHID)
            ancestorChain.append(nextPHID)
            cursor = nextPHID
        }

        var descendantChain: [String] = []
        cursor = focalPHID
        for _ in 0..<maxDepth {
            let edges = try await client.searchEdges(
                EdgeQuery(sourcePHIDs: [cursor], types: [.childrenOfSource])
            ).data
            if edges.isEmpty { break }
            if edges.count > 1 { truncated = true }
            let nextPHID = edges[0].destinationPHID
            if visited.contains(nextPHID) { break }
            visited.insert(nextPHID)
            descendantChain.append(nextPHID)
            cursor = nextPHID
        }

        let orderedPHIDs = ancestorChain.reversed() + [focalPHID] + descendantChain
        let allPHIDs = Array(orderedPHIDs)

        if allPHIDs.count == 1 {
            return RevisionStackGraph(ordered: [], focalID: focalID, truncatedAtBranch: false)
        }

        let revisionsResult = try await client.searchRevisions(
            RevisionQuery(
                constraints: RevisionQuery.Constraints(phids: allPHIDs),
                attachments: RevisionQuery.Attachments(
                    reviewers: true,
                    reviewersExtra: true,
                    subscribers: true,
                    projects: true
                )
            )
        )

        var byPHID: [String: Revision] = [:]
        for revision in revisionsResult.data {
            byPHID[revision.phid] = revision
            // Pre-warm only matches the .revision(id) loader's expected shape
            // (full attachments) — see ResourceCache.revision(id:).
            cache?.store(revision, for: .revision(revision.id))
        }

        let nodes: [RevisionStackGraph.Node] = allPHIDs.compactMap { phid in
            guard let rev = byPHID[phid] else { return nil }
            return RevisionStackGraph.Node(
                id: rev.id,
                phid: rev.phid,
                title: rev.fields.title,
                status: rev.fields.status,
                authorPHID: rev.fields.authorPHID
            )
        }

        return RevisionStackGraph(
            ordered: nodes,
            focalID: focalID,
            truncatedAtBranch: truncated
        )
    }
}
