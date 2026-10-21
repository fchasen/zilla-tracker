//
//  AttentionMonitor.swift
//  Zilla
//

import Foundation
import BugzillaKit
import PhabricatorKit
#if os(macOS)
import AppKit
#endif

@Observable
final class AttentionMonitor {
    private struct NeedsInfoResult {
        let login: String
        let bugs: [Bug]
    }

    private let auth: AuthStore
    private let phab: PhabricatorAuthStore
    private let workspace: Workspace
    private let cache: ResourceCache
    private let viewedBugs: ViewedBugsStore
    private let viewedRevisions: ViewedRevisionsStore
    private let revisionActivity: RevisionActivityStore

    private var needsInfoResult: NeedsInfoResult?
    private var revisionResults: [RevisionQuery: [Revision]] = [:]
    private var revisionsPolledPHID: String?
    private(set) var usernames: [String: String] = [:]
    private var unresolvedPHIDs: Set<String> = []

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var namesTask: Task<Void, Never>?
    #if os(macOS)
    @ObservationIgnored private var badgeTask: Task<Void, Never>?
    #endif

    init(
        auth: AuthStore,
        phab: PhabricatorAuthStore,
        workspace: Workspace,
        cache: ResourceCache,
        viewedBugs: ViewedBugsStore,
        viewedRevisions: ViewedRevisionsStore,
        revisionActivity: RevisionActivityStore
    ) {
        self.auth = auth
        self.phab = phab
        self.workspace = workspace
        self.cache = cache
        self.viewedBugs = viewedBugs
        self.viewedRevisions = viewedRevisions
        self.revisionActivity = revisionActivity
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        #if os(macOS)
        badgeTask = Task { [weak self] in
            let totals = Observations { [weak self] in self?.attentionTotal ?? 0 }
            for await total in totals {
                NSApplication.shared.dockTile.badgeLabel = total > 0 ? "\(total)" : nil
            }
        }
        #endif
        namesTask = Task { [weak self] in
            let pending = Observations { [weak self] in self?.unsettledPHIDs ?? [] }
            for await phids in pending where !phids.isEmpty {
                await self?.resolveUsernames()
            }
        }
        Task { await poll(force: false) }
    }

    var isSignedIn: Bool {
        auth.isSignedIn || phab.isSignedIn
    }

    func poll(force: Bool) async {
        async let needsInfo: Void = loadNeedsInfo(force: force)
        async let revisions: Void = loadRevisionBadges(force: force)
        _ = await (needsInfo, revisions)
    }

    var needsInfoBugs: [Bug] {
        currentNeedsInfo?.bugs ?? []
    }

    var needsInfoCount: Int? {
        currentNeedsInfo?.bugs.count
    }

    var needsInfoAttentionCount: Int {
        guard let login = currentLogin else { return 0 }
        return needsInfoBugs.filter {
            BugAttention.hasUnseenRequest($0, for: login, mark: viewedBugs.mark(for: $0.id))
        }.count
    }

    func loadNeedsInfo(force: Bool) async {
        guard let login = currentLogin else {
            needsInfoResult = nil
            return
        }
        var query = BugStatusFilter.all.apply(to: .needsReviewFromMe).substitutingMe(with: login)
        query.includeFields = ["id", "summary", "status", "creation_time", "last_change_time", "flags"]
        query.limit = 0
        guard let result = try? await cache.bugList(query, force: force, using: auth.client),
              currentLogin == login else { return }
        needsInfoResult = NeedsInfoResult(login: login, bugs: result.bugs)
    }

    private var currentLogin: String? {
        guard auth.isSignedIn, let login = auth.currentUser?.name, !login.isEmpty else { return nil }
        return login
    }

    private var currentNeedsInfo: NeedsInfoResult? {
        guard let login = currentLogin, let needsInfoResult, needsInfoResult.login == login else { return nil }
        return needsInfoResult
    }

    var reviewQuery: RevisionQuery? {
        guard let phid = phab.currentUser?.phid else { return nil }
        return .reviewing(responsiblePHID: phid, statuses: [RevisionStatus.Value.needsReview])
    }

    var patchesQuery: RevisionQuery? {
        guard let phid = phab.currentUser?.phid else { return nil }
        return .authored(authorPHID: phid, statuses: nil)
    }

    func revisions(for query: RevisionQuery?) -> [Revision] {
        loadedRevisions(for: query) ?? []
    }

    private func loadedRevisions(for query: RevisionQuery?) -> [Revision]? {
        guard let query else { return nil }
        if let page: RevisionPage = cache.get(.revisionSearchPages(query)) {
            return page.revisions
        }
        return revisionResults[query]
    }

    var visibleReviewRevisions: [Revision] {
        guard let viewerPHID = phab.currentUser?.phid else { return [] }
        return revisions(for: reviewQuery).filter { revision in
            guard revision.fields.authorPHID != viewerPHID else { return false }
            let scopes = ReviewerScope.scopes(
                for: revision,
                viewerPHID: viewerPHID,
                viewerProjectPHIDs: phab.viewerProjectPHIDs
            )
            return !scopes.allSatisfy { workspace.hiddenReviewerScopeIDs.contains($0.id) }
        }
    }

    var patchRevisions: [Revision] {
        revisions(for: patchesQuery)
    }

    var reviewAttentionCount: Int {
        visibleReviewRevisions.filter { needsAttention($0, in: .reviews) }.count
    }

    var patchAttentionCount: Int {
        patchRevisions.filter { needsAttention($0, in: .patches) }.count
    }

    var needsChangesCount: Int? {
        loadedRevisions(for: patchesQuery)?.filter {
            $0.fields.status.value == RevisionStatus.Value.needsRevision
        }.count
    }

    func needsAttention(_ revision: Revision, in list: RevisionList) -> Bool {
        RevisionAttention.needsAttention(
            in: list,
            mark: viewedRevisions.mark(for: revision.id),
            activity: revisionActivity.activity[revision.id]
        )
    }

    func loadRevisionBadges(force: Bool) async {
        guard phab.isSignedIn, let phid = phab.currentUser?.phid else {
            revisionResults = [:]
            revisionsPolledPHID = nil
            return
        }
        async let reviews = warmRevisions(reviewQuery, force: force)
        async let patches = warmRevisions(patchesQuery, force: force)
        let (reviewsLoaded, patchesLoaded) = await (reviews, patches)
        await refreshRevisionActivity()
        guard reviewsLoaded, patchesLoaded, phab.currentUser?.phid == phid else { return }
        revisionsPolledPHID = phid
    }

    private func warmRevisions(_ query: RevisionQuery?, force: Bool) async -> Bool {
        guard let query else { return false }
        do {
            let page = try await cache.revisionSearchAllPages(query, force: force, using: phab.client) { [weak self] page in
                self?.revisionResults[query] = page.revisions
                Task { await self?.refreshRevisionActivity() }
            }
            revisionResults[query] = page.revisions
            return true
        } catch {
            return false
        }
    }

    func refreshRevisionActivity() async {
        guard let viewerPHID = phab.currentUser?.phid else { return }
        let reviews = visibleReviewRevisions.filter {
            RevisionAttention.needsActivity($0, in: .reviews, mark: viewedRevisions.mark(for: $0.id))
        }
        let patches = patchRevisions.filter {
            RevisionAttention.needsActivity($0, in: .patches, mark: viewedRevisions.mark(for: $0.id))
        }
        await revisionActivity.refresh(reviews + patches, viewerPHID: viewerPHID, using: phab.client)
        await resolveUsernames()
    }

    private func resolveUsernames() async {
        let missing = namedPHIDs.subtracting(usernames.keys)
        guard !missing.isEmpty else { return }
        let users = await cache.resolveUsers(phids: Array(missing), using: phab.client)
        for (phid, user) in users {
            usernames[phid] = user.userName
        }
        unresolvedPHIDs.formUnion(missing.subtracting(users.keys))
    }

    private var namedPHIDs: Set<String> {
        var phids = Set(visibleReviewRevisions.map(\.fields.authorPHID))
        for revision in patchRevisions {
            if let actor = revisionActivity.activity[revision.id]?.latestNotifiable?.actorPHID {
                phids.insert(actor)
            }
        }
        return phids
    }

    private var unsettledPHIDs: Set<String> {
        namedPHIDs.subtracting(usernames.keys).subtracting(unresolvedPHIDs)
    }

    private func hasSettledName(_ phid: String) -> Bool {
        usernames[phid] != nil || unresolvedPHIDs.contains(phid)
    }

    var attentionTotal: Int {
        reviewAttentionCount + patchAttentionCount + needsInfoAttentionCount
    }

    var notificationSnapshot: NotificationSnapshot? {
        var polled: Set<NotificationCategory> = []
        var candidates: [NotificationCandidate] = []
        if let login = currentLogin, let needsInfo = currentNeedsInfo {
            polled.insert(.needinfo)
            candidates += AttentionCandidates.needinfo(
                needsInfo.bugs,
                viewer: login,
                marks: viewedBugs.marks
            )
        }
        if let phid = phab.currentUser?.phid, phab.isSignedIn, revisionsPolledPHID == phid {
            polled.formUnion([.review, .patch])
            candidates += AttentionCandidates.reviews(
                visibleReviewRevisions.filter { hasSettledName($0.fields.authorPHID) },
                marks: viewedRevisions.marks,
                activity: revisionActivity.activity,
                usernames: usernames
            )
            candidates += AttentionCandidates.patches(
                patchRevisions.filter { revision in
                    revisionActivity.activity[revision.id]?.latestNotifiable.map { hasSettledName($0.actorPHID) } ?? true
                },
                marks: viewedRevisions.marks,
                activity: revisionActivity.activity,
                usernames: usernames
            )
        }
        guard !polled.isEmpty else { return nil }
        return NotificationSnapshot(candidates: candidates, polled: polled)
    }
}

enum AttentionCandidates {
    static let fallbackName = "Someone"

    static func needinfo(_ bugs: [Bug], viewer: String, marks: [Int: SeenMark]) -> [NotificationCandidate] {
        bugs.compactMap { needinfo($0, viewer: viewer, mark: marks[$0.id]) }
    }

    static func needinfo(_ bug: Bug, viewer: String, mark: SeenMark?) -> NotificationCandidate? {
        guard BugAttention.hasUnseenRequest(bug, for: viewer, mark: mark),
              let requested = BugAttention.latestRequest(in: bug, for: viewer) else { return nil }
        let setter = bug.flags.first {
            $0.status == "?"
                && $0.requestee?.caseInsensitiveCompare(viewer) == .orderedSame
                && ($0.modificationDate ?? $0.creationDate) == requested
        }?.setter
        let title: String
        if let setter, !setter.isEmpty {
            title = "Needinfo from \(setter)"
        } else {
            title = "Needinfo request"
        }
        return NotificationCandidate(
            category: .needinfo,
            itemID: bug.id,
            eventDate: requested,
            title: title,
            subtitle: "Bug \(bug.id)",
            body: bug.summary,
            url: bugURL(bug.id)
        )
    }

    static func reviews(
        _ revisions: [Revision],
        marks: [Int: SeenMark],
        activity: [Revision.ID: RevisionActivity],
        usernames: [String: String]
    ) -> [NotificationCandidate] {
        revisions.compactMap {
            review(
                $0,
                mark: marks[$0.id],
                activity: activity[$0.id],
                authorName: usernames[$0.fields.authorPHID]
            )
        }
    }

    static func review(
        _ revision: Revision,
        mark: SeenMark?,
        activity: RevisionActivity?,
        authorName: String?
    ) -> NotificationCandidate? {
        guard RevisionAttention.needsAttention(in: .reviews, mark: mark, activity: activity) else { return nil }
        return NotificationCandidate(
            category: .review,
            itemID: revision.id,
            eventDate: activity?.latestFromOthers ?? revision.fields.dateCreated,
            title: "Review requested by \(authorName ?? fallbackName)",
            subtitle: "D\(revision.id)",
            body: revision.fields.title,
            url: revisionURL(revision.id)
        )
    }

    static func patches(
        _ revisions: [Revision],
        marks: [Int: SeenMark],
        activity: [Revision.ID: RevisionActivity],
        usernames: [String: String]
    ) -> [NotificationCandidate] {
        revisions.compactMap { revision in
            guard let event = RevisionAttention.notifiableEvent(
                mark: marks[revision.id],
                activity: activity[revision.id]
            ) else { return nil }
            return patch(revision, event: event, actorName: usernames[event.actorPHID])
        }
    }

    static func patch(_ revision: Revision, event: RevisionEvent, actorName: String?) -> NotificationCandidate {
        NotificationCandidate(
            category: .patch,
            itemID: revision.id,
            eventDate: event.date,
            title: "\(actorName ?? fallbackName) \(phrase(for: event.kind))",
            subtitle: "D\(revision.id)",
            body: revision.fields.title,
            url: revisionURL(revision.id)
        )
    }

    static func phrase(for kind: RevisionEventKind) -> String {
        switch kind {
        case .accepted: return "accepted your revision"
        case .requestedChanges: return "requested changes to your revision"
        case .resigned: return "resigned from your revision"
        case .commandeered: return "commandeered your revision"
        case .commented: return "commented on your revision"
        case .inlineCommented: return "left inline comments on your revision"
        case .landed: return "landed your revision"
        case .abandoned: return "abandoned your revision"
        case .reclaimed: return "reclaimed your revision"
        case .reopened: return "reopened your revision"
        case .statusChanged(let status):
            guard let status, !status.isEmpty else { return "changed your revision's status" }
            return "changed your revision's status to \(statusName(status))"
        }
    }

    static func statusName(_ value: String) -> String {
        switch value {
        case RevisionStatus.Value.draft: return "Draft"
        case RevisionStatus.Value.needsReview: return "Needs Review"
        case RevisionStatus.Value.needsRevision: return "Needs Revision"
        case RevisionStatus.Value.accepted: return "Accepted"
        case RevisionStatus.Value.changesPlanned: return "Changes Planned"
        case RevisionStatus.Value.published: return "Closed"
        case RevisionStatus.Value.abandoned: return "Abandoned"
        default: return value
        }
    }

    static func bugURL(_ id: Int) -> URL {
        URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(id)")!
    }

    static func revisionURL(_ id: Int) -> URL {
        URL(string: "https://phabricator.services.mozilla.com/D\(id)")!
    }
}
