//
//  ContentView.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BugzillaKit
import PhabricatorKit
import os
#if os(macOS)
import AppKit
#endif

private let revisionLog = Logger(subsystem: "com.zilla", category: "Revision")


// MARK: - Pills

struct BugTypePill: View {
    let type: String?
    var isMeta: Bool = false
    var linkTransfer: BugLinkTransfer? = nil

    var body: some View {
        if let info {
            if let transfer = linkTransfer {
                icon(info)
                    .draggable(transfer) {
                        Label("#\(transfer.id) \(transfer.summary)", systemImage: "ant")
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            } else {
                icon(info)
            }
        }
    }

    private func icon(_ info: (symbol: String, color: Color, label: String)) -> some View {
        Image(systemName: info.symbol)
            .foregroundStyle(info.color)
            .help(info.label)
            .accessibilityLabel(info.label)
    }

    private var info: (symbol: String, color: Color, label: String)? {
        if isMeta {
            return ("square.stack.fill", .purple, "Meta bug")
        }
        switch type?.lowercased() {
        case "defect": return ("ant.fill", .red, "Defect")
        case "enhancement": return ("sparkles", .indigo, "Enhancement")
        case "task": return ("clipboard", .gray, "Task")
        default:
            return linkTransfer == nil ? nil : ("ant.fill", .secondary, "Bug")
        }
    }
}

// MARK: - Drag payload

struct BugTransfer: Codable, Transferable {
    let id: Int
    let summary: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct BugLinkTransfer: Codable, Transferable {
    let id: Int
    let summary: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

// MARK: - Sidebar selection

enum SmartEndpoint: String, CaseIterable, Hashable, Identifiable {
    case myBugs
    case reported
    case needsReview
    case recentlyChanged
    case todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myBugs: return "My Bugs"
        case .reported: return "Reported"
        case .needsReview: return "Needs Info"
        case .recentlyChanged: return "Recently Changed"
        case .todo: return "Todo"
        }
    }

    var systemImage: String {
        switch self {
        case .myBugs: return "person.crop.circle"
        case .reported: return "tray.and.arrow.up"
        case .needsReview: return "flag"
        case .recentlyChanged: return "clock"
        case .todo: return "checklist"
        }
    }
}

enum ReviewList: String, CaseIterable, Hashable, Identifiable {
    case review
    case active
    case landed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .review: return "Review"
        case .landed: return "Landed"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "doc.text"
        case .review: return "checkmark.seal"
        case .landed: return "shippingbox"
        }
    }
}

enum SidebarSelection: Hashable {
    case smart(SmartEndpoint)
    case allDrafts
    case review(ReviewList)
    case component(ComponentRef)
    case metaBug(Int)
}

enum BugListSort: String, CaseIterable, Identifiable, Hashable {
    case rank, newest, recent, oldest, priority

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rank: return "Rank"
        case .newest: return "Newest"
        case .recent: return "Recent"
        case .oldest: return "Oldest"
        case .priority: return "Priority"
        }
    }

    var systemImage: String {
        switch self {
        case .rank: return "list.number"
        case .newest: return "arrow.down.circle"
        case .recent: return "clock"
        case .oldest: return "arrow.up.circle"
        case .priority: return "exclamationmark.triangle"
        }
    }

    var bmoOrder: String {
        switch self {
        case .rank: return "cf_rank,bug_id"
        case .priority: return "priority,bug_id"
        case .recent: return "changeddate DESC"
        case .newest: return "opendate DESC"
        case .oldest: return "opendate ASC"
        }
    }
}

enum BugStatusFilter: String, CaseIterable, Identifiable, Hashable {
    case all, open, new, assigned, closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .open: return "Open"
        case .new: return "New"
        case .assigned: return "Assigned"
        case .closed: return "Closed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .open: return "circle"
        case .new: return "sparkles"
        case .assigned: return "person.fill"
        case .closed: return "checkmark.circle"
        }
    }

    func apply(to query: BugQuery) -> BugQuery {
        var copy = query
        switch self {
        case .all:
            copy.status = []
            copy.resolution = []
        case .open:
            copy.status = []
            copy.resolution = ["---"]
        case .new:
            copy.status = ["NEW", "UNCONFIRMED", "REOPENED"]
            copy.resolution = ["---"]
        case .assigned:
            copy.status = ["ASSIGNED", "IN_PROGRESS"]
            copy.resolution = ["---"]
        case .closed:
            copy.status = ["RESOLVED", "VERIFIED", "CLOSED"]
            copy.resolution = []
        }
        return copy
    }
}

// MARK: - Type size

enum TypeSizeSettings {
    static let storageKey = "dynamicTypeSizeIndex"
    static let options: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
    ]
    static let defaultIndex = 3

    static func clamp(_ index: Int) -> Int {
        min(max(index, 0), options.count - 1)
    }
}

// MARK: - Workspace

struct DependencyMetadata: Sendable, Hashable {
    let id: Bug.ID
    let summary: String
    let status: String
    let resolution: String
    let type: String?
    let assigneeDisplayName: String?

    var isClosed: Bool {
        ["RESOLVED", "VERIFIED", "CLOSED"].contains(status.uppercased())
    }
}

@Observable
final class Workspace {
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?

    var sidebarSelection: SidebarSelection? = .smart(.myBugs) {
        didSet {
            if oldValue != sidebarSelection {
                activeRevisionID = nil
                pendingBackToRevision = nil
            }
        }
    }
    var selectedBugID: Bug.ID? {
        didSet {
            if oldValue != selectedBugID {
                activeRevisionID = nil
                // Don't clear pendingBackToRevision here — the navigation away
                // from a revision *to* a bug is exactly the case that sets it.
            }
        }
    }
    /// When the user navigates from a revision to its linked bug, this stores
    /// the revision ID so `BugDetailView` can render a back button that
    /// returns to the revision.
    var pendingBackToRevision: Int?

    @MainActor
    func returnToPendingRevision() {
        guard let id = pendingBackToRevision else { return }
        pendingBackToRevision = nil
        activeRevisionID = id
    }
    var selectedDraftID: UUID?
    var activeRevisionID: Int?
    var bugzillaSettingsPresented: Bool = false
    var phabricatorSettingsPresented: Bool = false
    var quickSearchPresented: Bool = false
    var lastUpdateError: String?
    var dupePromptRequested: Bool = false
    var newDraftRequested: Bool = false
    var searchText: String = ""
    var smartSorts: [SmartEndpoint: BugListSort] = [:]
    var componentSort: BugListSort = .priority
    var smartFilters: [SmartEndpoint: BugStatusFilter] = [:]
    var componentFilter: BugStatusFilter = .open
    var metaBugFilter: BugStatusFilter = .open
    var bugListRefreshToken: UUID = UUID()
    var revisionListRefreshToken: UUID = UUID()

    var typeSizeIndex: Int = (UserDefaults.standard.object(forKey: TypeSizeSettings.storageKey) as? Int) ?? TypeSizeSettings.defaultIndex {
        didSet {
            if oldValue != typeSizeIndex {
                UserDefaults.standard.set(typeSizeIndex, forKey: TypeSizeSettings.storageKey)
            }
        }
    }


    var bugListSort: BugListSort {
        get {
            if case let .smart(endpoint) = sidebarSelection {
                return smartSorts[endpoint] ?? Self.defaultSort(for: endpoint)
            }
            return componentSort
        }
        set {
            if case let .smart(endpoint) = sidebarSelection {
                smartSorts[endpoint] = newValue
            } else {
                componentSort = newValue
            }
        }
    }

    var bugStatusFilter: BugStatusFilter {
        get {
            switch sidebarSelection {
            case .smart(let endpoint):
                return smartFilters[endpoint] ?? Self.defaultFilter(for: endpoint)
            case .metaBug:
                return metaBugFilter
            case .component:
                return componentFilter
            case .allDrafts, .review, .none:
                return .all
            }
        }
        set {
            switch sidebarSelection {
            case .smart(let endpoint):
                smartFilters[endpoint] = newValue
            case .metaBug:
                metaBugFilter = newValue
            case .component:
                componentFilter = newValue
            case .allDrafts, .review, .none:
                break
            }
        }
    }

    private static func defaultSort(for endpoint: SmartEndpoint) -> BugListSort {
        switch endpoint {
        case .myBugs: return .rank
        default: return .recent
        }
    }

    private static func defaultFilter(for endpoint: SmartEndpoint) -> BugStatusFilter {
        switch endpoint {
        case .myBugs: return .open
        default: return .all
        }
    }

    // Active bug (loaded once per selection; shared with the inspector).
    private(set) var loadedBug: Bug?
    private(set) var loadedComments: [Comment] = []
    private(set) var isLoadingBug = false
    private(set) var bugLoadError: String?

    // Bug list loading flag, used by the (now centralized) refresh button.
    var isLoadingBugList: Bool = false

    // Bug-update flag, drives the toolbar progress indicator.
    private(set) var isUpdatingBug = false

    var lastLinkError: String?

    var showInspector: Bool = false

    var cache: ResourceCache?

    // Active revision (loaded once per selection; shared with the inspector).
    private(set) var loadedRevision: Revision?
    private(set) var loadedRevisionDiff: DiffDetail?
    private(set) var loadedRevisionTransactions: [RevisionTransaction] = []
    private(set) var loadedRevisionInlines: [InlineComment] = []
    private(set) var revisionUserDirectory: [String: PhabricatorUser] = [:]
    private(set) var changesetContent: [Int: ChangesetContentSource] = [:]
    private(set) var isLoadingRevision = false
    private(set) var revisionLoadError: String?
    private(set) var isUpdatingRevision = false

    var activeInlineComposer: ActiveInlineComposer?
    /// Paths that should be expanded in the diff. ChangesetView reads from
    /// this set rather than local state so external triggers (e.g. clicking
    /// a file link in the activity log) can pop a collapsed diff open.
    var expandedChangesets: Set<String> = []
    /// When set, RevisionDetailView's ScrollViewReader will scroll the matching
    /// changeset row to the top, then clear this back to nil.
    var pendingScrollToFile: String?

    /// When true, the activity stream hides everything that isn't a comment
    /// (status changes, reviewer additions, rebases, etc.). Persisted across
    /// launches via UserDefaults.
    static let activityShowAllStorageKey = "Zilla.activityShowAll"
    var activityShowAll: Bool = UserDefaults.standard.bool(forKey: Workspace.activityShowAllStorageKey) {
        didSet {
            if oldValue != activityShowAll {
                UserDefaults.standard.set(activityShowAll, forKey: Workspace.activityShowAllStorageKey)
            }
        }
    }

    func dependencyMetadata(for id: Bug.ID) -> DependencyMetadata? {
        cache?.dependencyMeta(for: id)
    }

    func loadProducts(using client: BugzillaClient) async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        loadError = nil
        defer { isLoadingProducts = false }
        do {
            let fetched: [Product]
            if let cache {
                fetched = try await cache.selectableProducts(using: client)
            } else {
                fetched = try await client.selectableProducts()
            }
            products = fetched
                .filter(\.isActive)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func reset() {
        products = []
        loadError = nil
        sidebarSelection = .smart(.myBugs)
        selectedBugID = nil
        selectedDraftID = nil
        activeRevisionID = nil
        searchText = ""
        clearLoadedBug()
        showInspector = false
        cache?.clear()
    }

    @MainActor
    func loadBug(id: Bug.ID, using client: BugzillaClient) async {
        isLoadingBug = true
        bugLoadError = nil
        defer { isLoadingBug = false }
        do {
            if let cache {
                async let bugTask = cache.bug(id: id, using: client) { [weak self] refreshed in
                    if self?.loadedBug?.id == id { self?.loadedBug = refreshed }
                }
                async let commentsTask = cache.comments(bugID: id, using: client) { [weak self] refreshed in
                    if self?.loadedBug?.id == id { self?.loadedComments = refreshed }
                }
                loadedBug = try await bugTask
                loadedComments = try await commentsTask
            } else {
                async let bugTask = client.getBug(id: id)
                async let commentsTask = client.comments(bugID: id)
                loadedBug = try await bugTask
                loadedComments = try await commentsTask
            }
        } catch is CancellationError {
            return
        } catch {
            loadedBug = nil
            loadedComments = []
            bugLoadError = error.localizedDescription
        }
    }

    @MainActor
    func clearLoadedBug() {
        loadedBug = nil
        loadedComments = []
        bugLoadError = nil
    }

    @discardableResult
    @MainActor
    func applyBugUpdate(_ update: BugUpdate, using client: BugzillaClient) async -> Error? {
        guard let id = loadedBug?.id else { return nil }
        isUpdatingBug = true
        defer { isUpdatingBug = false }
        do {
            _ = try await client.updateBug(id: id, update)
            cache?.invalidateBug(id: id)
            if let cache {
                if let refreshed = try? await cache.bug(id: id, force: true, using: client) {
                    loadedBug = refreshed
                }
                if let refreshed = try? await cache.comments(bugID: id, force: true, using: client) {
                    loadedComments = refreshed
                }
            } else {
                if let refreshed = try? await client.getBug(id: id) { loadedBug = refreshed }
                if let refreshed = try? await client.comments(bugID: id) { loadedComments = refreshed }
            }
            return nil
        } catch {
            return error
        }
    }

    @discardableResult
    @MainActor
    func linkBlocking(source: Bug.ID, target: Bug.ID, using client: BugzillaClient) async -> Error? {
        guard source != target else { return nil }
        if loadedBug?.id == source, loadedBug?.blocks.contains(target) == true {
            return nil
        }
        if loadedBug?.id == target, loadedBug?.dependsOn.contains(source) == true {
            return nil
        }
        isUpdatingBug = true
        defer { isUpdatingBug = false }
        do {
            _ = try await client.updateBug(
                id: source,
                BugUpdate(blocks: BugRelationUpdate(add: [target]))
            )
            cache?.invalidateBug(id: source)
            cache?.invalidateBug(id: target)
            if let id = loadedBug?.id, id == source || id == target {
                if let cache {
                    if let refreshed = try? await cache.bug(id: id, force: true, using: client) {
                        loadedBug = refreshed
                    }
                } else if let refreshed = try? await client.getBug(id: id) {
                    loadedBug = refreshed
                }
            }
            await loadDependencyMetadata(ids: [source, target], using: client)
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    func refreshLoadedComments(using client: BugzillaClient) async {
        guard let id = loadedBug?.id else { return }
        if let cache {
            if let refreshed = try? await cache.comments(bugID: id, force: true, using: client) {
                loadedComments = refreshed
            }
        } else if let refreshed = try? await client.comments(bugID: id) {
            loadedComments = refreshed
        }
    }

    @discardableResult
    @MainActor
    func updateComment(
        bugID: Bug.ID,
        commentID: Comment.ID,
        newText: String,
        using client: BugzillaClient
    ) async -> Error? {
        isUpdatingBug = true
        defer { isUpdatingBug = false }
        do {
            try await client.updateComment(bugID: bugID, commentID: commentID, newText: newText)
            cache?.invalidate(.comments(bugID: bugID))
            await refreshLoadedComments(using: client)
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    func loadDependencyMetadata(ids: [Bug.ID], using client: BugzillaClient) async {
        if let cache {
            await cache.loadDependencyMeta(ids: ids, using: client)
        }
    }

    @MainActor
    func clearLoadedRevision() {
        loadedRevision = nil
        loadedRevisionDiff = nil
        loadedRevisionTransactions = []
        loadedRevisionInlines = []
        revisionUserDirectory = [:]
        changesetContent = [:]
        revisionLoadError = nil
        activeInlineComposer = nil
        expandedChangesets = []
        pendingScrollToFile = nil
    }

    /// Expand the matching diff row and scroll to it. Called when the user
    /// taps a file path in the activity log.
    @MainActor
    func revealChangeset(path: String) {
        expandedChangesets.insert(path)
        pendingScrollToFile = path
    }

    @MainActor
    func loadRevision(id: Int, using client: PhabricatorClient) async {
        isLoadingRevision = true
        revisionLoadError = nil
        defer { isLoadingRevision = false }

        do {
            let revision: Revision
            if let cache {
                revision = try await cache.revision(id: id, using: client) { [weak self] refreshed in
                    guard let self else { return }
                    if self.loadedRevision?.id == id { self.loadedRevision = refreshed }
                }
            } else {
                let query = RevisionQuery(
                    constraints: RevisionQuery.Constraints(ids: [id]),
                    attachments: RevisionQuery.Attachments(reviewers: true, reviewersExtra: true, subscribers: true, projects: true)
                )
                let result = try await client.searchRevisions(query)
                guard let r = result.data.first else {
                    revisionLoadError = "Revision not found."
                    return
                }
                revision = r
            }
            loadedRevision = revision

            await loadRevisionAuxiliaries(revision: revision, using: client)
        } catch is CancellationError {
            return
        } catch {
            revisionLog.error("loadRevision failed: \(String(describing: error))")
            revisionLoadError = error.localizedDescription
        }
    }

    @MainActor
    private func loadRevisionAuxiliaries(revision: Revision, using client: PhabricatorClient) async {
        async let diffOpt: DiffDetail? = {
            do {
                if let cache {
                    return try await cache.revisionLatestDiff(
                        revisionPHID: revision.phid,
                        revisionID: revision.id,
                        using: client
                    )
                }
                let diffs = try await client.searchDiffs(.forRevision(revision.phid))
                guard let latest = diffs.data.first else { return nil }
                let details = try await client.getDiffs(ids: [latest.id])
                return details.first
            } catch is CancellationError {
                return nil
            } catch {
                revisionLog.error("Diff load failed: \(String(describing: error))")
                return nil
            }
        }()

        async let transactions: [RevisionTransaction] = {
            do {
                if let cache {
                    return try await cache.revisionTransactions(
                        id: revision.id,
                        revisionPHID: revision.phid,
                        using: client
                    )
                }
                return try await client.searchTransactions(
                    TransactionQuery(objectIdentifier: revision.phid, limit: 100)
                ).data
            } catch is CancellationError {
                return []
            } catch {
                revisionLog.error("Transaction load failed: \(String(describing: error))")
                return []
            }
        }()

        let resolvedDiff = await diffOpt
        let resolvedTransactions = await transactions
        let resolvedInlines = PhabricatorClient.inlineComments(from: resolvedTransactions)

        let typeCounts = Dictionary(
            grouping: resolvedTransactions,
            by: { $0.type ?? "<nil>" }
        ).mapValues { $0.count }
        revisionLog.notice("D\(revision.id): \(resolvedTransactions.count) transactions, \(resolvedInlines.count) inlines; type counts \(typeCounts)")
        if resolvedInlines.isEmpty {
            for tx in resolvedTransactions where tx.fields.path != nil || tx.fields.line != nil {
                revisionLog.notice("  inline-shaped tx type=\(tx.type ?? "<nil>") diffID=\(tx.fields.diffID.map(String.init) ?? "<nil>") path=\(tx.fields.path ?? "<nil>") line=\(tx.fields.line.map(String.init) ?? "<nil>") commentBody=\(tx.comments.last?.content.raw?.prefix(40).description ?? "<nil>")")
            }
        }

        guard loadedRevision?.id == revision.id else { return }
        loadedRevisionDiff = resolvedDiff
        loadedRevisionTransactions = resolvedTransactions
        loadedRevisionInlines = resolvedInlines

        await resolveUserDirectory(using: client)
        await loadChangesetContent(using: client)
    }

    @MainActor
    private func resolveUserDirectory(using client: PhabricatorClient) async {
        var phids: Set<String> = []
        if let revision = loadedRevision {
            phids.insert(revision.fields.authorPHID)
            for reviewer in revision.attachments?.reviewers?.reviewers ?? [] {
                phids.insert(reviewer.reviewerPHID)
            }
        }
        for transaction in loadedRevisionTransactions {
            if let phid = transaction.authorPHID { phids.insert(phid) }
        }
        for inline in loadedRevisionInlines {
            if let phid = inline.authorPHID { phids.insert(phid) }
        }
        if let cache {
            let resolved = await cache.resolveUsers(phids: Array(phids), using: client)
            revisionUserDirectory.merge(resolved) { _, new in new }
        } else if let users = try? await client.searchUsers(phids: Array(phids)) {
            for user in users {
                revisionUserDirectory[user.phid] = user
            }
        }
    }

    @MainActor
    private func loadChangesetContent(using client: PhabricatorClient) async {
        guard let diff = loadedRevisionDiff else { return }
        let loader = ChangesetContentLoader(client: client, cache: cache)
        let activeRevID = loadedRevision?.id
        await withTaskGroup(of: (Int, ChangesetContentSource).self) { group in
            for changeset in diff.changesets {
                group.addTask { @MainActor in
                    let source = await loader.load(changeset, diff: diff)
                    return (changeset.id, source)
                }
            }
            for await (id, source) in group {
                guard loadedRevision?.id == activeRevID else { continue }
                changesetContent[id] = source
            }
        }
    }

    @discardableResult
    @MainActor
    func applyRevisionEdit(
        transactions: [RevisionEditTransaction],
        using client: PhabricatorClient
    ) async -> Error? {
        guard let revision = loadedRevision else { return nil }
        isUpdatingRevision = true
        defer { isUpdatingRevision = false }
        do {
            _ = try await client.editRevision(objectIdentifier: revision.phid, transactions: transactions)
            cache?.invalidateRevision(id: revision.id)
            await loadRevision(id: revision.id, using: client)
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    func refreshRevisionActivity(using client: PhabricatorClient) async {
        guard let revision = loadedRevision else { return }
        cache?.invalidate(.revisionTransactions(revision.id))
        let refreshed: [RevisionTransaction]?
        if let cache {
            refreshed = try? await cache.revisionTransactions(
                id: revision.id,
                revisionPHID: revision.phid,
                force: true,
                using: client
            )
        } else {
            refreshed = try? await client.searchTransactions(
                TransactionQuery(objectIdentifier: revision.phid, limit: 100)
            ).data
        }
        if let refreshed {
            loadedRevisionTransactions = refreshed
            loadedRevisionInlines = PhabricatorClient.inlineComments(from: refreshed)
        }
        await resolveUserDirectory(using: client)
    }

    /// Opens an in-diff composer at `(path, line)`. If a composer is already
    /// open elsewhere, it's replaced.
    @MainActor
    func beginInlineComposer(
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        replyTo: String?
    ) {
        activeInlineComposer = ActiveInlineComposer(
            path: path,
            line: line,
            length: length,
            isNewFile: isNewFile,
            replyTo: replyTo
        )
    }

    @MainActor
    func cancelInlineComposer() {
        activeInlineComposer = nil
    }

    @MainActor
    func createInlineDraft(
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        content: String,
        replyTo replyToCommentPHID: String?,
        using client: PhabricatorClient
    ) async -> Error? {
        guard let diff = loadedRevisionDiff, let revision = loadedRevision else { return nil }
        do {
            _ = try await client.createInlineComment(
                diffID: diff.id,
                path: path,
                line: line,
                length: length,
                isNewFile: isNewFile,
                content: content,
                replyToCommentPHID: replyToCommentPHID
            )
            cache?.invalidate(.revisionTransactions(revision.id))
            await refreshRevisionActivity(using: client)
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    func deleteInlineDraft(phid: String, using client: PhabricatorClient) async -> Error? {
        guard let revision = loadedRevision else { return nil }
        do {
            try await client.deleteDraftInline(phid: phid)
            cache?.invalidate(.revisionTransactions(revision.id))
            await refreshRevisionActivity(using: client)
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    func editInlineDraft(
        phid: String,
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        replyTo replyToCommentPHID: String?,
        newContent: String,
        using client: PhabricatorClient
    ) async -> Error? {
        if let error = await deleteInlineDraft(phid: phid, using: client) {
            return error
        }
        return await createInlineDraft(
            path: path,
            line: line,
            length: length,
            isNewFile: isNewFile,
            content: newContent,
            replyTo: replyToCommentPHID,
            using: client
        )
    }

    func bugQuery(for selection: SidebarSelection) -> BugQuery {
        switch selection {
        case .smart(.myBugs):
            return .myBugs
        case .smart(.reported):
            return .reportedByMe
        case .smart(.needsReview):
            return .needsReviewFromMe
        case .smart(.recentlyChanged):
            return .recentlyChanged(involving: BugQuery.me)
        case .smart(.todo):
            return BugQuery()
        case .component(let ref):
            return .openIn(component: ref)
        case .metaBug(let id):
            return .blockedBy(metaBug: id)
        case .allDrafts, .review:
            return BugQuery()
        }
    }

    static var preview: Workspace {
        let ws = Workspace()
        ws.products = [
            Product(
                id: 1, name: "Firefox", description: "Browser", isActive: true,
                components: [
                    Component(id: 11, name: "General", description: ""),
                    Component(id: 12, name: "Theme", description: "")
                ]
            ),
            Product(
                id: 2, name: "Core", description: "Engine", isActive: true,
                components: [
                    Component(id: 21, name: "DOM: Core & HTML", description: "")
                ]
            )
        ]
        return ws
    }
}

// MARK: - Root

struct ContentView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.modelContext) private var modelContext
    @Query private var followedMetaBugs: [FollowedMetaBug]

    private var currentTypeSize: DynamicTypeSize {
        TypeSizeSettings.options[TypeSizeSettings.clamp(workspace.typeSizeIndex)]
    }

    var body: some View {
        @Bindable var workspace = workspace

        NavigationSplitView {
            Sidebar(selection: $workspace.sidebarSelection)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .dynamicTypeSize(currentTypeSize)
        .inspector(isPresented: $workspace.showInspector) {
            inspectorColumn
                .inspectorColumnWidth(min: 220, ideal: 280, max: 360)
        }
        .sheet(isPresented: $workspace.bugzillaSettingsPresented) {
            BugzillaSettingsView()
        }
        .sheet(isPresented: $workspace.phabricatorSettingsPresented) {
            PhabricatorSettingsView()
        }
        .sheet(isPresented: $workspace.quickSearchPresented) {
            QuickSearchSheet { bugID in
                workspace.selectedBugID = bugID
            }
        }
        .alert(
            "Couldn't link bugs",
            isPresented: Binding(
                get: { workspace.lastLinkError != nil },
                set: { if !$0 { workspace.lastLinkError = nil } }
            ),
            actions: { Button("OK") { workspace.lastLinkError = nil } },
            message: { Text(workspace.lastLinkError ?? "") }
        )
        .alert(
            "Couldn't update bug",
            isPresented: Binding(
                get: { workspace.lastUpdateError != nil },
                set: { if !$0 { workspace.lastUpdateError = nil } }
            ),
            actions: { Button("OK") { workspace.lastUpdateError = nil } },
            message: { Text(workspace.lastUpdateError ?? "") }
        )
        .task(id: auth.isSignedIn) {
            if auth.isSignedIn, workspace.products.isEmpty {
                await workspace.loadProducts(using: auth.client)
            } else if !auth.isSignedIn {
                workspace.bugzillaSettingsPresented = true
            }
        }
        .onChange(of: workspace.newDraftRequested) { _, requested in
            if requested {
                workspace.newDraftRequested = false
                createDraft()
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        @Bindable var workspace = workspace
        switch workspace.sidebarSelection {
        case .review(let list):
            RevisionListView(list: list)
        default:
            BugListView(selection: workspace.sidebarSelection,
                        selectedBugID: $workspace.selectedBugID,
                        onNewBug: createDraft,
                        newBugHelp: newBugHelpText)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = workspace.activeRevisionID {
            RevisionDetailView(revisionID: id) {
                workspace.activeRevisionID = nil
            }
        } else if workspace.sidebarSelection == .allDrafts, let id = workspace.selectedDraftID {
            DraftEditorView(draftID: id)
        } else {
            BugDetailView(bugID: workspace.selectedBugID)
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if workspace.activeRevisionID != nil {
            RevisionInspector()
        } else if workspace.sidebarSelection == .allDrafts, let id = workspace.selectedDraftID {
            DraftInspector(draftID: id)
        } else {
            BugInspector()
        }
    }

    private var newBugHelpText: String {
        switch workspace.sidebarSelection {
        case .component(let ref):
            return "New bug in \(ref.component)"
        case .metaBug(let id):
            return "New bug blocking #\(id)"
        case .smart, .allDrafts, .review, .none:
            return "New bug…"
        }
    }

    private func createDraft() {
        let draft = BugDraft()
        switch workspace.sidebarSelection {
        case .component(let ref):
            draft.product = ref.product
            draft.componentName = ref.component
        case .metaBug(let bugId):
            if let meta = followedMetaBugs.first(where: { $0.bugId == bugId }),
               let parent = meta.component {
                draft.product = parent.product
                draft.componentName = parent.componentName
            }
            draft.blocks = [bugId]
        case .smart, .allDrafts, .review, .none:
            break
        }
        modelContext.insert(draft)
        workspace.sidebarSelection = .allDrafts
        workspace.selectedDraftID = draft.id
        workspace.showInspector = true
    }
}

private struct BugInspector: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    var body: some View {
        if let bug = workspace.loadedBug {
            ScrollView {
                BugInspectorContent(
                    bug: bug,
                    onUpdate: { update in
                        Task { await workspace.applyBugUpdate(update, using: auth.client) }
                    },
                    onOpenBug: { id in
                        workspace.selectedBugID = id
                    }
                )
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "No bug selected",
                systemImage: "sidebar.right",
                description: Text("Select a bug to see its details.")
            )
        }
    }
}

private struct DraftInspector: View {
    let draftID: UUID

    @Query private var matchingDrafts: [BugDraft]

    init(draftID: UUID) {
        self.draftID = draftID
        self._matchingDrafts = Query(filter: #Predicate<BugDraft> { $0.id == draftID })
    }

    var body: some View {
        if let draft = matchingDrafts.first {
            ScrollView {
                DraftMetadata(draft: draft)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "No draft",
                systemImage: "sidebar.right",
                description: Text("Pick a draft on the left.")
            )
        }
    }
}

private struct DraftMetadata: View {
    @Bindable var draft: BugDraft

    @State private var showComponentPicker = false

    private static let typeOptions: [(code: String?, label: String)] = [
        (nil, "—"),
        ("defect", "Defect"),
        ("enhancement", "Enhancement"),
        ("task", "Task")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            componentSection
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                typeRow
                menuRow(
                    label: "Priority",
                    current: draft.priority,
                    options: BugMetadata.priorityOptions
                ) { value in
                    draft.priority = (value == "--") ? nil : value
                    draft.updatedAt = .now
                }
                menuRow(
                    label: "Severity",
                    current: draft.severity,
                    options: BugMetadata.severityOptions
                ) { value in
                    draft.severity = (value == "--") ? nil : value
                    draft.updatedAt = .now
                }
                assigneeRow
                keywordsRow
                whiteboardRow
                blocksRow
                datesRow
            }
        }
        .font(.callout)
        .sheet(isPresented: $showComponentPicker) {
            ComponentPickerSheet(onPick: { product, component in
                draft.product = product.name
                draft.componentName = component.name
                draft.updatedAt = .now
            })
        }
    }

    @ViewBuilder
    private var componentSection: some View {
        let isMetaSeeded = !draft.blocks.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Text("Component").foregroundStyle(.secondary).font(.caption)
            if let ref = draft.componentRef {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ref.component)
                        Text(ref.product)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !isMetaSeeded {
                        Button("Change…") { showComponentPicker = true }
                            .buttonStyle(.borderless)
                    }
                }
            } else {
                Button {
                    showComponentPicker = true
                } label: {
                    Label("Pick component…", systemImage: "shippingbox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            if isMetaSeeded {
                Text("Inherited from blocked meta bug")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var typeRow: some View {
        GridRow {
            Text("Type").foregroundStyle(.secondary)
            Menu {
                ForEach(Self.typeOptions, id: \.label) { option in
                    Button {
                        draft.type = option.code
                        draft.updatedAt = .now
                    } label: {
                        if option.code == draft.type {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Text(typeLabel)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var typeLabel: String {
        Self.typeOptions.first(where: { $0.code == draft.type })?.label ?? "—"
    }

    @ViewBuilder
    private func menuRow(
        label: String,
        current: String?,
        options: [String],
        onPick: @escaping (String) -> Void
    ) -> some View {
        let displayed = (current?.isEmpty == false ? current : nil) ?? "--"
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Menu {
                ForEach(options, id: \.self) { value in
                    Button {
                        onPick(value)
                    } label: {
                        if value == current || (value == "--" && (current == nil || current?.isEmpty == true)) {
                            Label(value, systemImage: "checkmark")
                        } else {
                            Text(value)
                        }
                    }
                }
            } label: {
                Text(displayed)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var assigneeRow: some View {
        GridRow {
            Text("Assignee").foregroundStyle(.secondary)
            TextField("default assignee", text: Binding(
                get: { draft.assignedTo ?? "" },
                set: { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.assignedTo = trimmed.isEmpty ? nil : newValue
                    draft.updatedAt = .now
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var keywordsRow: some View {
        GridRow {
            Text("Keywords").foregroundStyle(.secondary)
            TextField("comma-separated", text: $draft.keywordsCSV)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft.keywordsCSV) { draft.updatedAt = .now }
        }
    }

    @ViewBuilder
    private var whiteboardRow: some View {
        GridRow {
            Text("Whiteboard").foregroundStyle(.secondary)
            TextField("[tag1][tag2]…", text: $draft.whiteboard)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft.whiteboard) { draft.updatedAt = .now }
        }
    }

    @ViewBuilder
    private var blocksRow: some View {
        if !draft.blocks.isEmpty {
            GridRow {
                Text("Blocks").foregroundStyle(.secondary)
                Text(draft.blocks.map { "#\($0)" }.joined(separator: ", "))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var datesRow: some View {
        GridRow {
            Text("Updated").foregroundStyle(.secondary)
            Text(draft.updatedAt, format: .relative(presentation: .named))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthStore.self) private var auth
    @Environment(Workspace.self) private var workspace
    @Query(sort: [SortDescriptor(\FollowedComponent.position),
                  SortDescriptor(\FollowedComponent.addedAt)])
    private var followedComponents: [FollowedComponent]
    @Query(sort: [SortDescriptor(\BugDraft.updatedAt, order: .reverse)])
    private var drafts: [BugDraft]

    @Binding var selection: SidebarSelection?

    @State private var addMetaBugTarget: FollowedComponent?
    @State private var showAddComponent = false

    @AppStorage("sidebar.section.review.expanded") private var reviewExpanded = true
    @AppStorage("sidebar.section.components.expanded") private var componentsExpanded = true

    var body: some View {
        List(selection: $selection) {
                Section {
                    ForEach(SmartEndpoint.allCases) { endpoint in
                        if endpoint == .todo {
                            TodoSidebarRow()
                                .tag(SidebarSelection.smart(endpoint))
                        } else {
                            Label(endpoint.title, systemImage: endpoint.systemImage)
                                .tag(SidebarSelection.smart(endpoint))
                        }
                    }
                    Label {
                        HStack {
                            Text("Drafts")
                            Spacer()
                            if !drafts.isEmpty {
                                Text("\(drafts.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tag(SidebarSelection.allDrafts)
                }

                Section(isExpanded: $reviewExpanded) {
                    ForEach(ReviewList.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(SidebarSelection.review(item))
                    }
                } header: {
                    Text("Review")
                }

                Section(isExpanded: $componentsExpanded) {
                    if followedComponents.isEmpty {
                        Text("No components yet. Tap + above to follow one.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(followedComponents) { followed in
                            FollowedComponentEntry(
                                followed: followed,
                                onAddMetaBug: { addMetaBugTarget = followed }
                            )
                        }
                        .onMove(perform: moveComponents)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text("Components")
                        Spacer()
                        Button {
                            showAddComponent = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Add Component")
                    }
                }
            }
        .navigationTitle("Zilla")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                accountMenu
            }
        }
        .sheet(item: $addMetaBugTarget) { component in
            MetaBugPickerSheet(component: component)
        }
        .sheet(isPresented: $showAddComponent) {
            ComponentPickerSheet()
        }
    }

    private func moveComponents(from source: IndexSet, to destination: Int) {
        var items = followedComponents
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.position = index
        }
    }

    @ViewBuilder
    private var accountMenu: some View {
        Menu {
            if let user = auth.currentUser {
                Text(user.realName ?? user.name)
                if let nick = user.nick {
                    Text("@\(nick)")
                }
                Divider()
                Button("Bugzilla…") {
                    workspace.bugzillaSettingsPresented = true
                }
                Button("Phabricator…") {
                    workspace.phabricatorSettingsPresented = true
                }
                Divider()
                Button("Sign Out", role: .destructive) {
                    Task {
                        await auth.signOut()
                        workspace.reset()
                    }
                }
            } else {
                Button("Sign In to Bugzilla…") {
                    workspace.bugzillaSettingsPresented = true
                }
                Button("Phabricator…") {
                    workspace.phabricatorSettingsPresented = true
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .help("Account")
    }
}

private struct DraftRow: View {
    let draft: BugDraft

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.displaySummary).lineLimit(1)
                Text(draft.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.and.pencil")
        }
    }
}

private struct AllDraftsList: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\BugDraft.updatedAt, order: .reverse)])
    private var drafts: [BugDraft]

    private func duplicate(_ draft: BugDraft) {
        let copy = BugDraft(
            product: draft.product,
            componentName: draft.componentName,
            blocks: draft.blocks
        )
        copy.summary = draft.summary
        copy.bugDescription = draft.bugDescription
        copy.version = draft.version
        copy.type = draft.type
        copy.severity = draft.severity
        copy.priority = draft.priority
        copy.assignedTo = draft.assignedTo
        copy.keywordsCSV = draft.keywordsCSV
        copy.whiteboard = draft.whiteboard
        modelContext.insert(copy)
        workspace.selectedDraftID = copy.id
    }

    var body: some View {
        @Bindable var workspace = workspace

        Group {
            if drafts.isEmpty {
                ContentUnavailableView(
                    "No drafts",
                    systemImage: "square.and.pencil",
                    description: Text("Tap + to start a new bug.")
                )
            } else {
                List(selection: $workspace.selectedDraftID) {
                    ForEach(drafts) { draft in
                        DraftListRow(draft: draft)
                            .tag(Optional(draft.id))
                            .contextMenu {
                                Button("Duplicate") {
                                    duplicate(draft)
                                }
                                Divider()
                                Button("Discard", role: .destructive) {
                                    if workspace.selectedDraftID == draft.id {
                                        workspace.selectedDraftID = nil
                                    }
                                    modelContext.delete(draft)
                                }
                            }
                    }
                }
            }
        }
    }
}

private struct DraftListRow: View {
    let draft: BugDraft

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.secondary)
                .imageScale(.large)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(draft.displaySummary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(draft.displaySubtitle)
                    if let firstBlocks = draft.blocks.first {
                        Text(verbatim: "·")
                        Text("blocks #\(firstBlocks)")
                    }
                    Text(verbatim: "·")
                    Text(draft.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct FollowedComponentEntry: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    let followed: FollowedComponent
    let onAddMetaBug: () -> Void

    @State private var isDropTarget = false
    @AppStorage private var isExpanded: Bool

    init(followed: FollowedComponent, onAddMetaBug: @escaping () -> Void) {
        self.followed = followed
        self.onAddMetaBug = onAddMetaBug
        self._isExpanded = AppStorage(
            wrappedValue: true,
            "sidebar.component.\(followed.product)::\(followed.componentName).expanded"
        )
    }

    var body: some View {
        let metas = followed.metaBugs.sorted {
            ($0.position, $0.addedAt) < ($1.position, $1.addedAt)
        }

        DisclosureGroup(isExpanded: $isExpanded) {
            Label("Open Bugs", systemImage: "tray.full")
                .tag(SidebarSelection.component(followed.ref))
            ForEach(metas) { meta in
                FollowedMetaBugRow(meta: meta)
                    .tag(SidebarSelection.metaBug(meta.bugId))
                    .contextMenu {
                        Button("Open in Bugzilla") {
                            if let url = URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(meta.bugId)") {
                                openURL(url)
                            }
                        }
                        Button("Copy Bug Link") {
                            copyToPasteboard("https://bugzilla.mozilla.org/show_bug.cgi?id=\(meta.bugId)")
                        }
                        Divider()
                        Button("Remove", role: .destructive) {
                            modelContext.delete(meta)
                        }
                    }
            }
            .onMove { source, destination in
                moveMetas(metas, from: source, to: destination)
            }
        } label: {
            FollowedComponentRow(followed: followed)
                .contextMenu { componentMenu }
        }
        .background(
            isDropTarget
                ? Color.accentColor.opacity(0.18)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .dropDestination(for: BugTransfer.self) { transfers, _ in
            var inserted = false
            for transfer in transfers where !followed.metaBugs.contains(where: { $0.bugId == transfer.id }) {
                let nextPosition = (followed.metaBugs.map(\.position).max() ?? -1) + 1 + (inserted ? 1 : 0)
                let meta = FollowedMetaBug(
                    bugId: transfer.id,
                    summary: transfer.summary,
                    component: followed,
                    position: nextPosition
                )
                modelContext.insert(meta)
                inserted = true
            }
            return inserted
        } isTargeted: { isDropTarget = $0 }
    }

    @ViewBuilder
    private var componentMenu: some View {
        Button("Add Meta Bug…") { onAddMetaBug() }
        Button("Copy Component Path") {
            copyToPasteboard("\(followed.product) :: \(followed.componentName)")
        }
        Divider()
        Button("Remove", role: .destructive) {
            modelContext.delete(followed)
        }
    }

    private func moveMetas(_ metas: [FollowedMetaBug], from source: IndexSet, to destination: Int) {
        var items = metas
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.position = index
        }
    }
}

private struct FollowedComponentRow: View {
    let followed: FollowedComponent

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(followed.componentName).lineLimit(1)
                Text(followed.product)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.stack.3d.up")
        }
    }
}

private struct TodoSidebarRow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BugOrderEntry> { $0.endpointKey == "todo" },
           sort: [SortDescriptor(\BugOrderEntry.position)])
    private var todoOrder: [BugOrderEntry]
    @State private var isDropTarget = false

    var body: some View {
        Label(SmartEndpoint.todo.title, systemImage: SmartEndpoint.todo.systemImage)
            .background(
                isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .dropDestination(for: BugTransfer.self) { transfers, _ in
                var nextPosition = (todoOrder.last?.position ?? -1) + 1
                var inserted = false
                for transfer in transfers where !todoOrder.contains(where: { $0.bugId == transfer.id }) {
                    let entry = BugOrderEntry(
                        endpointKey: BugOrderEntry.todoKey,
                        bugId: transfer.id,
                        position: nextPosition
                    )
                    modelContext.insert(entry)
                    nextPosition += 1
                    inserted = true
                }
                return inserted
            } isTargeted: { isDropTarget = $0 }
    }
}

private struct FollowedMetaBugRow: View {
    let meta: FollowedMetaBug

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(FollowedMetaBug.cleanedSummary(meta.summary)).lineLimit(1)
                Text(verbatim: "#\(meta.bugId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "circle.dashed")
        }
    }
}

// MARK: - Bug list

struct BugNode: Identifiable, Hashable {
    let bug: Bug
    var children: [BugNode]?

    var id: Bug.ID { bug.id }

    static func == (lhs: BugNode, rhs: BugNode) -> Bool {
        lhs.bug.id == rhs.bug.id && lhs.children == rhs.children
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bug.id)
    }
}

struct BugListView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(ResourceCache.self) private var cache
    @Environment(ViewedBugsStore.self) private var viewedBugs
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\FollowedComponent.position),
                  SortDescriptor(\FollowedComponent.addedAt)])
    private var followedComponents: [FollowedComponent]
    @Query private var followedMetaBugs: [FollowedMetaBug]
    @Query(filter: #Predicate<BugOrderEntry> { $0.endpointKey == "todo" },
           sort: [SortDescriptor(\BugOrderEntry.position)])
    private var todoOrder: [BugOrderEntry]

    let selection: SidebarSelection?
    @Binding var selectedBugID: Bug.ID?
    var onNewBug: () -> Void = {}
    var newBugHelp: String = "New bug…"

    @State private var bugs: [Bug] = []
    @State private var dependents: [Bug.ID: [Bug]] = [:]
    @State private var totalMatches: Int?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var loadError: String?
    @State private var lastSeenRefreshToken: UUID?

    private static let pageLimit = 50

    private var isAllDrafts: Bool {
        selection == .allDrafts
    }

    private var isRanked: Bool {
        workspace.bugListSort == .rank
    }

    private var isTodo: Bool {
        selection == .smart(.todo)
    }

    var body: some View {
        Group {
            if !auth.isSignedIn && !isAllDrafts {
                signedOutPlaceholder
            } else if selection == nil {
                ContentUnavailableView(
                    "Pick something",
                    systemImage: "sidebar.left",
                    description: Text("Choose a smart list or component on the left.")
                )
            } else if isAllDrafts {
                AllDraftsList()
            } else if isLoading && bugs.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load bugs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else if bugs.isEmpty {
                if isTodo {
                    ContentUnavailableView(
                        "Nothing to do yet",
                        systemImage: "checklist",
                        description: Text("Drag bugs here from any list, or right-click a bug and choose ‘Add to Todo’.")
                    )
                } else {
                    ContentUnavailableView(
                        "No bugs",
                        systemImage: "tray",
                        description: Text("Nothing matches this filter.")
                    )
                }
            } else {
                let nodes = rootNodes
                List(selection: $selectedBugID) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, root in
                        OutlineGroup(root, children: \.children) { node in
                            let topIdx: Int? = node.id == root.id ? index : nil
                            row(for: node.bug, topIndex: topIdx, displayed: sortedBugs)
                                .onAppear {
                                    if let topIdx, topIdx >= nodes.count - 5 {
                                        Task { await loadMore() }
                                    }
                                }
                        }
                    }
                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Spacer()
                        }
                    } else if canLoadMore {
                        Button("Load more") {
                            Task { await loadMore() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationTitle(title)
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 360, ideal: 460)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewBug()
                } label: {
                    Label("New Bug", systemImage: "plus")
                }
                .help(newBugHelp)
            }
            if !isAllDrafts && auth.isSignedIn {
                ToolbarItem(placement: .primaryAction) {
                    refreshButton
                }
                if !isTodo {
                    ToolbarItem(placement: .primaryAction) {
                        sortMenu
                    }
                    ToolbarItem(placement: .primaryAction) {
                        filterMenu
                    }
                }
            }
        }
        .searchableIf(!isTodo, text: searchBinding, prompt: "Search bugs")
        .task(id: loadKey) {
            let current = workspace.bugListRefreshToken
            let force = lastSeenRefreshToken != nil && lastSeenRefreshToken != current
            lastSeenRefreshToken = current
            await load(force: force)
        }
        .onChange(of: selection) { _, _ in
            bugs = []
            dependents = [:]
            totalMatches = nil
            canLoadMore = false
            loadError = nil
        }
    }

    private var searchBinding: Binding<String> {
        @Bindable var workspace = workspace
        return $workspace.searchText
    }

    private var signedOutPlaceholder: some View {
        ContentUnavailableView {
            Label("Bugzilla not connected", systemImage: "key")
        } description: {
            Text("Add your Bugzilla API key to load and update bugs.")
        } actions: {
            Button("Sign In to Bugzilla…") {
                workspace.bugzillaSettingsPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var refreshButton: some View {
        Button {
            workspace.bugListRefreshToken = UUID()
        } label: {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .help("Refresh")
        .disabled(isLoading)
    }

    private var sortMenu: some View {
        @Bindable var workspace = workspace
        return Menu {
            Picker(selection: $workspace.bugListSort) {
                ForEach(availableSorts) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort bug list")
    }

    private var filterMenu: some View {
        @Bindable var workspace = workspace
        return Menu {
            Picker(selection: $workspace.bugStatusFilter) {
                ForEach(BugStatusFilter.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: filterIcon)
        }
        .help("Filter by status")
    }

    private var filterIcon: String {
        workspace.bugStatusFilter == .all
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    private var availableSorts: [BugListSort] {
        BugListSort.allCases
    }

    private var sortedBugs: [Bug] {
        bugs
    }

    @ViewBuilder
    private func row(for bug: Bug, topIndex: Int?, displayed: [Bug]) -> some View {
        BugRow(bug: bug)
            .tag(Optional(bug.id))
            .draggable(BugTransfer(id: bug.id, summary: bug.summary)) {
                Label("#\(bug.id) \(bug.summary)", systemImage: "ant")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .bugLinkDrop(target: bug.id)
            .bugReorderDrop(
                bugID: bug.id,
                indexInList: topIndex ?? 0,
                displayed: displayed,
                isEnabled: topIndex != nil && (isRanked || isTodo),
                onReorder: { id, rank, order in
                    if isTodo {
                        applyTodoOrder(order ?? sortedBugs)
                    } else {
                        applyRank(bugID: id, rank: rank, optimisticOrder: order)
                    }
                }
            )
            .contextMenu {
                rowQuickActions(for: bug)
                Divider()
                addAsMetaMenu(for: bug)
            }
    }

    @ViewBuilder
    private func rowQuickActions(for bug: Bug) -> some View {
        Button("Open in Bugzilla") {
            if let url = URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bug.id)") {
                openURL(url)
            }
        }
        Button("Copy Bug Link") {
            copyToPasteboard("https://bugzilla.mozilla.org/show_bug.cgi?id=\(bug.id)")
        }
        Button("Copy Bug ID") {
            copyToPasteboard(String(bug.id))
        }
        Divider()
        if viewedBugs.contains(bug.id) {
            Button("Mark as Unviewed") {
                viewedBugs.markUnviewed(bug.id)
            }
        } else {
            Button("Mark as Viewed") {
                viewedBugs.markViewed(bug.id)
            }
        }
        if BugStatuses.isUnassigned(bug.assignedTo), let me = auth.currentUser?.name {
            Button("Take") {
                takeBug(bug, as: me)
            }
        }
        if isRanked, bug.rank != nil {
            Button("Clear Rank") {
                applyRank(bugID: bug.id, rank: 0, optimisticOrder: nil)
            }
        }
        Divider()
        if todoOrder.contains(where: { $0.bugId == bug.id }) {
            Button("Remove from Todo") {
                removeBugFromTodo(bug.id)
            }
        } else {
            Button("Add to Todo") {
                addBugToTodo(bug.id)
            }
        }
    }

    private func takeBug(_ bug: Bug, as username: String) {
        let client = auth.client
        Task {
            do {
                _ = try await client.updateBug(id: bug.id, BugUpdate(assignedTo: username))
                workspace.bugListRefreshToken = UUID()
                if workspace.loadedBug?.id == bug.id {
                    _ = await workspace.applyBugUpdate(BugUpdate(assignedTo: username), using: client)
                }
            } catch {
                workspace.lastUpdateError = error.localizedDescription
            }
        }
    }

    private func applyRank(bugID: Bug.ID, rank: Int, optimisticOrder: [Bug]?) {
        if let optimisticOrder {
            bugs = optimisticOrder
        }
        let client = auth.client
        Task {
            do {
                _ = try await client.updateBug(id: bugID, BugUpdate(rank: rank))
                cache.invalidateBug(id: bugID)
            } catch {
                workspace.lastUpdateError = error.localizedDescription
            }
            workspace.bugListRefreshToken = UUID()
        }
    }

    private func applyTodoOrder(_ order: [Bug]) {
        bugs = order
        let positionByID: [Int: Int] = Dictionary(
            uniqueKeysWithValues: order.enumerated().map { ($1.id, $0) }
        )
        for entry in todoOrder {
            if let pos = positionByID[entry.bugId], entry.position != pos {
                entry.position = pos
            }
        }
    }

    private func addBugToTodo(_ bugID: Bug.ID) {
        guard !todoOrder.contains(where: { $0.bugId == bugID }) else { return }
        let nextPosition = (todoOrder.last?.position ?? -1) + 1
        let entry = BugOrderEntry(
            endpointKey: BugOrderEntry.todoKey,
            bugId: bugID,
            position: nextPosition
        )
        modelContext.insert(entry)
    }

    private func removeBugFromTodo(_ bugID: Bug.ID) {
        if let entry = todoOrder.first(where: { $0.bugId == bugID }) {
            modelContext.delete(entry)
        }
        if selectedBugID == bugID {
            selectedBugID = nil
        }
    }

    private var rootNodes: [BugNode] {
        sortedBugs.map { bug in
            guard Self.isMetaSummary(bug.summary),
                  let deps = dependents[bug.id], !deps.isEmpty else {
                return BugNode(bug: bug, children: nil)
            }
            return BugNode(
                bug: bug,
                children: deps.map { BugNode(bug: $0, children: nil) }
            )
        }
    }

    static func isMetaSummary(_ summary: String) -> Bool {
        summary.range(of: #"^\s*\[meta\]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    @ViewBuilder
    private func addAsMetaMenu(for bug: Bug) -> some View {
        if followedComponents.isEmpty {
            Button("Add To…") {}
                .disabled(true)
        } else {
            Menu("Add To") {
                ForEach(followedComponents) { followed in
                    Button("\(followed.componentName)  ·  \(followed.product)") {
                        addBugAsMeta(bug, to: followed)
                    }
                    .disabled(followed.metaBugs.contains { $0.bugId == bug.id })
                }
            }
        }
    }

    private func addBugAsMeta(_ bug: Bug, to followed: FollowedComponent) {
        guard !followed.metaBugs.contains(where: { $0.bugId == bug.id }) else { return }
        let nextPosition = (followed.metaBugs.map(\.position).max() ?? -1) + 1
        let meta = FollowedMetaBug(
            bugId: bug.id,
            summary: bug.summary,
            component: followed,
            position: nextPosition
        )
        modelContext.insert(meta)
    }

    private var loadKey: BugListLoadKey {
        BugListLoadKey(
            selection: selection,
            search: workspace.searchText,
            sort: workspace.bugListSort,
            filter: workspace.bugStatusFilter,
            refresh: workspace.bugListRefreshToken,
            signedIn: auth.isSignedIn,
            todoIDs: isTodo ? todoOrder.map(\.bugId) : []
        )
    }

    private var title: String {
        guard let selection else { return "Zilla" }
        switch selection {
        case .smart(let s): return s.title
        case .component(let ref): return "\(ref.product) :: \(ref.component)"
        case .metaBug(let id):
            if let meta = followedMetaBugs.first(where: { $0.bugId == id }),
               !meta.summary.isEmpty {
                return meta.summary
            }
            return "Meta \(id)"
        case .allDrafts: return "Drafts"
        case .review(let r): return r.title
        }
    }

    private static let bugIncludeFields = [
        "id", "summary", "status", "resolution", "product", "component",
        "assigned_to", "priority", "severity", "keywords", "type",
        "last_change_time", "creation_time", "cf_rank",
        "attachments.id", "attachments.content_type", "attachments.is_obsolete"
    ]

    private func makeQuery(offset: Int) -> BugQuery? {
        guard let selection else { return nil }
        var query = workspace.bugQuery(for: selection)
        if let login = auth.currentUser?.name {
            query = query.substitutingMe(with: login)
        }
        query = workspace.bugStatusFilter.apply(to: query)
        let trimmed = workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.quicksearch = trimmed
        }
        query.limit = Self.pageLimit
        query.offset = offset
        query.order = workspace.bugListSort.bmoOrder
        query.includeFields = Self.bugIncludeFields
        return query
    }

    private func load(force: Bool) async {
        guard let selection else {
            bugs = []
            totalMatches = nil
            canLoadMore = false
            return
        }
        if selection == .allDrafts {
            bugs = []
            totalMatches = nil
            canLoadMore = false
            return
        }
        guard auth.isSignedIn else {
            bugs = []
            totalMatches = nil
            canLoadMore = false
            loadError = nil
            return
        }

        if isTodo {
            let ids = todoOrder.map(\.bugId)
            if ids.isEmpty {
                bugs = []
                dependents = [:]
                totalMatches = 0
                canLoadMore = false
                loadError = nil
                return
            }
            isLoading = true
            workspace.isLoadingBugList = true
            loadError = nil
            defer {
                isLoading = false
                workspace.isLoadingBugList = false
            }
            do {
                let fetched = try await auth.client.getBugs(ids: ids)
                let positionByID: [Int: Int] = Dictionary(
                    uniqueKeysWithValues: todoOrder.map { ($0.bugId, $0.position) }
                )
                bugs = fetched.sorted {
                    (positionByID[$0.id] ?? .max) < (positionByID[$1.id] ?? .max)
                }
                dependents = [:]
                totalMatches = fetched.count
                canLoadMore = false
            } catch is CancellationError {
                return
            } catch {
                loadError = error.localizedDescription
                bugs = []
                totalMatches = nil
                canLoadMore = false
            }
            return
        }

        if !force {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }

        guard let query = makeQuery(offset: 0) else { return }

        isLoading = true
        workspace.isLoadingBugList = true
        loadError = nil
        defer {
            isLoading = false
            workspace.isLoadingBugList = false
        }

        do {
            let result = try await cache.bugList(query, force: force, using: auth.client)
            bugs = result.bugs
            dependents = [:]
            totalMatches = result.totalMatches
            canLoadMore = hasMore(loaded: result.bugs.count, fetched: result.bugs.count, total: result.totalMatches)
            await fetchDependents(for: result.bugs.filter { Self.isMetaSummary($0.summary) }.map(\.id))
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            bugs = []
            totalMatches = nil
            canLoadMore = false
        }
    }

    private func loadMore() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        guard let query = makeQuery(offset: bugs.count) else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await auth.client.searchBugs(query)
            let existing = Set(bugs.map(\.id))
            let appended = result.bugs.filter { !existing.contains($0.id) }
            bugs.append(contentsOf: appended)
            if let total = result.totalMatches { totalMatches = total }
            canLoadMore = hasMore(loaded: bugs.count, fetched: result.bugs.count, total: result.totalMatches ?? totalMatches)
            await fetchDependents(for: appended.filter { Self.isMetaSummary($0.summary) }.map(\.id))
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            canLoadMore = false
        }
    }

    private func fetchDependents(for metaIDs: [Bug.ID]) async {
        guard !metaIDs.isEmpty else { return }
        let login = auth.currentUser?.name
        let client = auth.client
        let fields = Self.bugIncludeFields
        let filter = workspace.bugStatusFilter

        let results = await withTaskGroup(of: (Bug.ID, [Bug])?.self) { group in
            for id in metaIDs {
                group.addTask {
                    var query = BugQuery.blockedBy(metaBug: id)
                    if let login {
                        query = query.substitutingMe(with: login)
                    }
                    query = filter.apply(to: query)
                    query.limit = 100
                    query.includeFields = fields
                    guard let result = try? await client.searchBugs(query) else {
                        return nil
                    }
                    return (id, result.bugs)
                }
            }
            var collected: [(Bug.ID, [Bug])] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }
        for (id, bugs) in results {
            dependents[id] = bugs
        }
    }

    private func hasMore(loaded: Int, fetched: Int, total: Int?) -> Bool {
        if let total { return loaded < total }
        return fetched == Self.pageLimit
    }
}

private struct BugListLoadKey: Hashable {
    let selection: SidebarSelection?
    let search: String
    let sort: BugListSort
    let filter: BugStatusFilter
    let refresh: UUID
    let signedIn: Bool
    let todoIDs: [Int]
}

private struct BugReorderDropModifier: ViewModifier {
    let bugID: Bug.ID
    let indexInList: Int
    let displayed: [Bug]
    let isEnabled: Bool
    let onReorder: (Bug.ID, Int, [Bug]?) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.overlay {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .dropDestination(for: BugTransfer.self) { transfers, _ in
                            handleDrop(transfers, zoneIndex: indexInList)
                        } isTargeted: { _ in }
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .dropDestination(for: BugTransfer.self) { transfers, _ in
                            handleDrop(transfers, zoneIndex: indexInList + 1)
                        } isTargeted: { _ in }
                }
            }
        } else {
            content
        }
    }

    private func handleDrop(_ transfers: [BugTransfer], zoneIndex: Int) -> Bool {
        guard let transfer = transfers.first else { return false }
        if transfer.id == bugID { return false }
        reorder(bugID: transfer.id, zoneIndex: zoneIndex)
        return true
    }

    private func reorder(bugID: Bug.ID, zoneIndex: Int) {
        let removeIdx = displayed.firstIndex(where: { $0.id == bugID })
        var newOrder = displayed
        if let idx = removeIdx {
            newOrder.remove(at: idx)
        }
        let insertIdx: Int
        if let removeIdx, removeIdx < zoneIndex {
            insertIdx = max(0, zoneIndex - 1)
        } else {
            insertIdx = min(zoneIndex, newOrder.count)
        }
        guard let bug = displayed.first(where: { $0.id == bugID }) else { return }
        if let removeIdx, removeIdx == insertIdx {
            return
        }
        newOrder.insert(bug, at: insertIdx)

        let newRank = computeRank(for: bugID, in: newOrder)
        onReorder(bugID, newRank, newOrder)
    }

    /// Picks a cf_rank value that places `bugID` between its new neighbours.
    /// Uses sparse spacing (multiples of `Self.rankStep`) so subsequent drops
    /// can wedge bugs between without rebalancing every neighbour.
    private func computeRank(for bugID: Bug.ID, in order: [Bug]) -> Int {
        guard let pos = order.firstIndex(where: { $0.id == bugID }) else {
            return Self.rankStep
        }
        let prev = pos > 0 ? order[pos - 1].rank : nil
        let next = pos + 1 < order.count ? order[pos + 1].rank : nil
        switch (prev, next) {
        case (nil, nil):
            return Self.rankStep
        case (let p?, nil):
            return p + Self.rankStep
        case (nil, let n?):
            return n > Self.rankStep ? n - Self.rankStep : max(1, n / 2)
        case (let p?, let n?) where n - p > 1:
            return p + (n - p) / 2
        case (let p?, _):
            return p + Self.rankStep
        }
    }

    private static let rankStep = 100
}

extension View {
    func bugReorderDrop(
        bugID: Bug.ID,
        indexInList: Int,
        displayed: [Bug],
        isEnabled: Bool,
        onReorder: @escaping (Bug.ID, Int, [Bug]?) -> Void
    ) -> some View {
        modifier(BugReorderDropModifier(
            bugID: bugID,
            indexInList: indexInList,
            displayed: displayed,
            isEnabled: isEnabled,
            onReorder: onReorder
        ))
    }

    @ViewBuilder
    func searchableIf(_ isActive: Bool, text: Binding<String>, prompt: String) -> some View {
        if isActive {
            self.searchable(text: text, prompt: Text(prompt))
        } else {
            self
        }
    }
}

private struct BugRow: View {
    @Environment(ViewedBugsStore.self) private var viewedBugs
    let bug: Bug

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .imageScale(.large)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(displaySummary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                ViewThatFits(in: .horizontal) {
                    metadataLine(level: 0)
                    metadataLine(level: 1)
                    metadataLine(level: 2)
                    metadataLine(level: 3)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var displaySummary: String {
        FollowedMetaBug.cleanedSummary(bug.summary)
    }

    private var isMeta: Bool {
        bug.summary.range(of: #"^\s*\[meta\]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private var isClosed: Bool {
        ["RESOLVED", "VERIFIED", "CLOSED"].contains(bug.status.uppercased())
    }

    private var isUnseenAndRecent: Bool {
        guard !isClosed,
              !viewedBugs.contains(bug.id),
              let created = bug.creationTime else { return false }
        return Date().timeIntervalSince(created) < 7 * 24 * 60 * 60
    }

    private var statusIcon: String {
        if isClosed { return "checkmark.circle.fill" }
        if bug.hasPhabricatorPatch { return "circle.lefthalf.filled" }
        switch bug.status.uppercased() {
        case "ASSIGNED": return "circle"
        case "IN_PROGRESS": return "circle.lefthalf.filled"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        if isClosed { return .green }
        if bug.hasPhabricatorPatch { return .blue }
        switch bug.status.uppercased() {
        case "ASSIGNED", "IN_PROGRESS": return .blue
        default: return .secondary
        }
    }

    private var displayPriority: String? {
        guard let p = bug.priority, !p.isEmpty, p != "--" else { return nil }
        return p
    }

    private var displaySeverity: String? {
        guard let s = bug.severity, !s.isEmpty, s != "--" else { return nil }
        return s
    }

    private func priorityColor(_ value: String?) -> Color {
        switch value?.uppercased() {
        case "P1": return .red
        case "P2": return .orange
        default: return .secondary
        }
    }

    private func severityColor(_ value: String?) -> Color {
        switch value?.uppercased() {
        case "S1", "BLOCKER", "CRITICAL": return .red
        case "S2", "MAJOR": return .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private func metadataLine(level: Int) -> some View {
        HStack(spacing: 6) {
            if isUnseenAndRecent {
                Circle()
                    .fill(.blue)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("New")
            }
            BugTypePill(type: bug.type, isMeta: isMeta)
            Text(verbatim: "\(bug.id)")
            Text(verbatim: "·")
            Text(bug.status.bugzillaTitleCased)
            if level <= 2, let priority = displayPriority {
                Text(verbatim: "·")
                Text(priority)
                    .foregroundStyle(priorityColor(bug.priority))
            }
            if level <= 1, let severity = displaySeverity {
                Text(verbatim: "·")
                Text(severity)
                    .foregroundStyle(severityColor(bug.severity))
            }
            if level <= 0, let when = bug.lastChangeTime {
                Text(verbatim: "·")
                Text(when, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            }
        }
        .lineLimit(1)
    }
}

extension String {
    var bugzillaTitleCased: String {
        replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview {
    ContentView()
        .environment(Workspace.preview)
        .environment(AuthStore())
        .environment(ViewedBugsStore())
        .environment(ResourceCache())
}
