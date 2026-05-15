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
import FolioCodeView
import os
#if os(macOS)
import AppKit
#endif

private let revisionLog = Logger(subsystem: "com.zilla", category: "Revision")


struct EmptyStateIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 56, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


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
    case needsReview
    case triage
    case todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myBugs: return "My Bugs"
        case .needsReview: return "Needs Info"
        case .triage: return "Triage"
        case .todo: return "Todo"
        }
    }

    var systemImage: String {
        switch self {
        case .myBugs: return "tray"
        case .needsReview: return "flag"
        case .triage: return "ant"
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

enum RevisionStatusFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case draft
    case needsReview
    case needsRevision
    case accepted
    case changesPlanned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .draft: return "Draft"
        case .needsReview: return "Needs Review"
        case .needsRevision: return "Needs Revision"
        case .accepted: return "Accepted"
        case .changesPlanned: return "Changes Planned"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .draft: return "pencil.line"
        case .needsReview: return "eye"
        case .needsRevision: return "arrow.triangle.2.circlepath"
        case .accepted: return "checkmark.seal"
        case .changesPlanned: return "calendar"
        }
    }

    var queryStatuses: [String]? {
        switch self {
        case .all: return nil
        case .draft: return [RevisionStatus.Value.draft]
        case .needsReview: return [RevisionStatus.Value.needsReview]
        case .needsRevision: return [RevisionStatus.Value.needsRevision]
        case .accepted: return [RevisionStatus.Value.accepted]
        case .changesPlanned: return [RevisionStatus.Value.changesPlanned]
        }
    }
}

enum SidebarSelection: Hashable {
    case smart(SmartEndpoint)
    case allDrafts
    case review(ReviewList)
    case component(ComponentRef)
    case componentTriage(ComponentRef)
    case componentBoard(ComponentRef)
    case metaBug(Int)
}

enum DetailRoute: Hashable {
    case bug(Bug.ID)
    case revision(Int)
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
    case all, open, new, assigned, reported, closed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .open: return "Open"
        case .new: return "New"
        case .assigned: return "Assigned"
        case .reported: return "Reported"
        case .closed: return "Closed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .open: return "circle"
        case .new: return "sparkles"
        case .assigned: return "person.fill"
        case .reported: return "tray.and.arrow.up"
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
        case .reported:
            copy.status = []
            copy.resolution = []
            copy.reporter = [BugQuery.me]
        case .closed:
            copy.status = ["RESOLVED", "VERIFIED", "CLOSED"]
            copy.resolution = []
        }
        return copy
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

    var sidebarSelection: SidebarSelection? = Workspace.defaultSidebarSelection {
        didSet {
            if oldValue != sidebarSelection {
                activeRevisionID = nil
                detailPath = []
            }
        }
    }

    static var defaultSidebarSelection: SidebarSelection? {
        #if os(macOS)
        return .smart(.myBugs)
        #else
        return nil
        #endif
    }
    var selectedBugID: Bug.ID? {
        didSet {
            if oldValue != selectedBugID {
                activeRevisionID = nil
                detailPath = []
            }
        }
    }
    var selectedDraftID: UUID?
    var activeRevisionID: Int? {
        didSet {
            if oldValue != activeRevisionID {
                detailPath = []
            }
        }
    }
    var detailPath: [DetailRoute] = []

    private var rootRoute: DetailRoute? {
        if let id = activeRevisionID {
            return .revision(id)
        }
        if sidebarSelection == .allDrafts {
            return nil
        }
        if let id = selectedBugID {
            return .bug(id)
        }
        return nil
    }

    @MainActor
    func navigate(to route: DetailRoute) {
        if route == rootRoute {
            detailPath = []
            return
        }
        if let idx = detailPath.firstIndex(of: route) {
            detailPath = Array(detailPath.prefix(idx + 1))
            return
        }
        detailPath.append(route)
    }

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
    var revisionStatusFilters: [ReviewList: RevisionStatusFilter] = [:]

    func revisionStatusFilter(for list: ReviewList) -> RevisionStatusFilter {
        revisionStatusFilters[list] ?? Self.defaultRevisionStatusFilter(for: list)
    }

    private static func defaultRevisionStatusFilter(for list: ReviewList) -> RevisionStatusFilter {
        switch list {
        case .active: return .all
        case .review: return .needsReview
        case .landed: return .all
        }
    }

    var fontScaleStep: Int = FontScale.clamp(
        (UserDefaults.standard.object(forKey: FontScale.storageKey) as? Int) ?? FontScale.defaultStep
    ) {
        didSet {
            if oldValue != fontScaleStep {
                UserDefaults.standard.set(fontScaleStep, forKey: FontScale.storageKey)
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
            case .component, .componentTriage, .componentBoard:
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
            case .component, .componentTriage, .componentBoard:
                componentFilter = newValue
            case .allDrafts, .review, .none:
                break
            }
        }
    }

    private static func defaultSort(for endpoint: SmartEndpoint) -> BugListSort {
        switch endpoint {
        case .myBugs: return .rank
        case .triage: return .newest
        default: return .recent
        }
    }

    private static func defaultFilter(for endpoint: SmartEndpoint) -> BugStatusFilter {
        switch endpoint {
        case .myBugs, .triage: return .open
        default: return .all
        }
    }

    func ownedComponentRefs(for login: String?) -> [ComponentRef] {
        guard let login, !login.isEmpty else { return [] }
        return products.flatMap { product -> [ComponentRef] in
            guard product.isActive else { return [] }
            return product.components
                .filter { component in
                    guard component.isActive, let triageOwner = component.triageOwner else { return false }
                    return triageOwner.caseInsensitiveCompare(login) == .orderedSame
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { ComponentRef(product: product.name, component: $0.name) }
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

    var showInspector: Bool = {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }()

    var cache: ResourceCache?

    // Active revision (loaded once per selection; shared with the inspector).
    private(set) var loadedRevision: Revision?
    private(set) var loadedRevisionDiff: DiffDetail?
    private(set) var loadedRevisionTransactions: [RevisionTransaction] = []
    private(set) var loadedRevisionInlines: [InlineComment] = []
    private(set) var loadedRevisionStack: RevisionStackGraph?
    private(set) var revisionUserDirectory: [String: PhabricatorUser] = [:]
    private(set) var revisionProjectDirectory: [String: PhabricatorProject] = [:]
    private(set) var testingTagPHIDs: [TestingTag: String] = [:]
    private(set) var changesetContent: [Int: ChangesetContentSource] = [:]
    private(set) var isLoadingRevision = false
    private(set) var revisionLoadError: String?
    private(set) var isUpdatingRevision = false

    var activeInlineComposer: ActiveInlineComposer?

    var bugCommentDrafts: [Bug.ID: String] = [:]
    var revisionCommentDrafts: [Int: String] = [:]
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
        sidebarSelection = Workspace.defaultSidebarSelection
        selectedBugID = nil
        selectedDraftID = nil
        activeRevisionID = nil
        searchText = ""
        clearLoadedBug()
        #if os(macOS)
        showInspector = true
        #else
        showInspector = false
        #endif
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

    @MainActor
    func publishLoadedBug(_ bug: Bug, comments: [Comment]) {
        loadedBug = bug
        loadedComments = comments
        bugLoadError = nil
    }

    @discardableResult
    @MainActor
    func restoreCachedBug(id: Bug.ID) -> Bool {
        guard let cache,
              let bug: Bug = cache.get(.bug(id)) else { return false }
        let comments: [Comment] = cache.get(.comments(bugID: id)) ?? []
        publishLoadedBug(bug, comments: comments)
        return true
    }

    @discardableResult
    @MainActor
    func applyBugUpdate(_ update: BugUpdate, using client: BugzillaClient) async -> Error? {
        guard let id = loadedBug?.id else { return nil }
        return await applyBugUpdate(id: id, update, using: client)
    }

    @discardableResult
    @MainActor
    func applyBugUpdate(id: Bug.ID, _ update: BugUpdate, using client: BugzillaClient) async -> Error? {
        isUpdatingBug = true
        defer { isUpdatingBug = false }
        do {
            _ = try await client.updateBug(id: id, update)
            cache?.invalidateBug(id: id)
            if loadedBug?.id == id {
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
    func publishLoadedRevision(
        _ revision: Revision,
        diff: DiffDetail?,
        transactions: [RevisionTransaction],
        inlines: [InlineComment],
        stack: RevisionStackGraph? = nil
    ) {
        loadedRevision = revision
        loadedRevisionDiff = diff
        loadedRevisionTransactions = transactions
        loadedRevisionInlines = inlines
        loadedRevisionStack = stack
        revisionLoadError = nil
    }

    @discardableResult
    @MainActor
    func restoreCachedRevision(id: Int) -> Bool {
        guard let cache,
              let revision: Revision = cache.get(.revision(id)) else { return false }
        let cachedDiff: DiffDetail?? = cache.get(.revisionDiff(id), as: Optional<DiffDetail>.self)
        let transactions: [RevisionTransaction] = cache.get(.revisionTransactions(id)) ?? []
        let stack: RevisionStackGraph? = cache.get(.revisionStack(id))
        publishLoadedRevision(
            revision,
            diff: cachedDiff ?? nil,
            transactions: transactions,
            inlines: PhabricatorClient.inlineComments(from: transactions),
            stack: stack
        )
        return true
    }

    func clearLoadedRevision() {
        loadedRevision = nil
        loadedRevisionDiff = nil
        loadedRevisionTransactions = []
        loadedRevisionInlines = []
        loadedRevisionStack = nil
        revisionUserDirectory = [:]
        revisionProjectDirectory = [:]
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

        async let stackOpt: RevisionStackGraph? = {
            guard let cache else { return nil }
            do {
                return try await cache.revisionStack(
                    revisionID: revision.id,
                    revisionPHID: revision.phid,
                    using: client
                )
            } catch is CancellationError {
                return nil
            } catch {
                revisionLog.error("Stack load failed: \(String(describing: error))")
                return nil
            }
        }()

        let resolvedDiff = await diffOpt
        let resolvedTransactions = await transactions
        let resolvedStack = await stackOpt
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
        loadedRevisionStack = resolvedStack

        await resolveUserDirectory(using: client)
        await resolveProjectDirectory(using: client)
        await loadChangesetContent(using: client)
    }

    @MainActor
    func cacheProjects(_ projects: [PhabricatorProject]) {
        for project in projects {
            revisionProjectDirectory[project.phid] = project
            if let tag = TestingTag.match(project) {
                testingTagPHIDs[tag] = project.phid
            }
        }
    }

    @MainActor
    func loadTestingTagDirectory(using client: PhabricatorClient) async {
        let needed = TestingTag.allCases.filter { testingTagPHIDs[$0] == nil }
        guard !needed.isEmpty else { return }
        let slugs = needed.map(\.rawValue)
        do {
            let result = try await client.searchProjects(
                ProjectQuery(
                    constraints: ProjectQuery.Constraints(slugs: slugs),
                    limit: slugs.count
                )
            )
            for project in result.data {
                revisionProjectDirectory[project.phid] = project
                if let tag = TestingTag.match(project) {
                    testingTagPHIDs[tag] = project.phid
                }
            }
        } catch {
            revisionLog.error("Testing tag lookup failed: \(String(describing: error))")
        }
    }

    @MainActor
    private func resolveProjectDirectory(using client: PhabricatorClient) async {
        var phids: Set<String> = []
        for phid in loadedRevision?.attachments?.projects?.projectPHIDs ?? [] {
            phids.insert(phid)
        }
        for reviewer in loadedRevision?.attachments?.reviewers?.reviewers ?? [] {
            if reviewer.reviewerPHID.hasPrefix("PHID-PROJ-") {
                phids.insert(reviewer.reviewerPHID)
            }
        }
        for transaction in loadedRevisionTransactions {
            for phid in transaction.referencedPHIDs where phid.hasPrefix("PHID-PROJ-") {
                phids.insert(phid)
            }
        }
        let missing = phids.filter { revisionProjectDirectory[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            let result = try await client.searchProjects(.byPHIDs(Array(missing)))
            for project in result.data {
                revisionProjectDirectory[project.phid] = project
            }
        } catch {
            revisionLog.error("Project lookup failed: \(String(describing: error))")
        }
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
            for referenced in transaction.referencedPHIDs {
                phids.insert(referenced)
            }
        }
        for inline in loadedRevisionInlines {
            if let phid = inline.authorPHID { phids.insert(phid) }
        }
        for node in loadedRevisionStack?.ordered ?? [] {
            phids.insert(node.authorPHID)
        }
        let userPHIDs = phids.filter { $0.hasPrefix("PHID-USER-") }
        if let cache {
            let resolved = await cache.resolveUsers(phids: Array(userPHIDs), using: client)
            revisionUserDirectory.merge(resolved) { _, new in new }
        } else if let users = try? await client.searchUsers(phids: Array(userPHIDs)) {
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

    @MainActor
    func beginInlineComposer(
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        replyTo: String?,
        editingPHID: String? = nil
    ) {
        activeInlineComposer = ActiveInlineComposer(
            path: path,
            line: line,
            length: length,
            isNewFile: isNewFile,
            replyTo: replyTo,
            editingPHID: editingPHID
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
        replyTo: String? = nil,
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
                replyToCommentPHID: replyTo
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

    /// Phabricator stores `isDone` on the *transaction* that introduced the
    /// thread head, keyed by its comments. Walk the loaded transactions and
    /// build a lookup keyed by every contained comment PHID so callers can
    /// resolve the done state from any comment in the thread.
    var inlineDoneStates: [String: Bool] {
        var result: [String: Bool] = [:]
        for transaction in loadedRevisionTransactions {
            guard transaction.fields.replyToCommentPHID == nil,
                  let isDone = transaction.fields.isDone else { continue }
            for comment in transaction.comments where (comment.removed ?? false) == false {
                result[comment.phid] = isDone
            }
        }
        return result
    }

    @MainActor
    func setInlineDone(commentPHID: String, isDone: Bool, using client: PhabricatorClient) async -> Error? {
        guard let revision = loadedRevision else { return nil }
        do {
            _ = try await client.editRevision(
                objectIdentifier: revision.phid,
                transactions: [.inlineDone([commentPHID: isDone])]
            )
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
        newContent: String,
        replyTo: String? = nil,
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
            replyTo: replyTo,
            using: client
        )
    }

    func bugQuery(for selection: SidebarSelection) -> BugQuery {
        switch selection {
        case .smart(.myBugs):
            return .myBugs
        case .smart(.needsReview):
            return .needsReviewFromMe
        case .smart(.triage):
            return .triage
        case .smart(.todo):
            return BugQuery()
        case .component(let ref), .componentBoard(let ref):
            return .openIn(component: ref)
        case .componentTriage(let ref):
            return .triage(in: ref)
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

    var body: some View {
        @Bindable var workspace = workspace

        NavigationSplitView {
            Sidebar(selection: $workspace.sidebarSelection)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .dynamicTypeSize(FontScale.dynamicTypeSize(for: workspace.fontScaleStep))
        .environment(\.zillaFontScale, FontScale.multiplier(for: workspace.fontScaleStep))
        .environment(\.folioFontScale, FontScale.multiplier(for: workspace.fontScaleStep))
        .inspector(isPresented: $workspace.showInspector) {
            inspectorColumn
                .inspectorColumnWidth(min: 220, ideal: 342, max: 360)
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
            if !auth.isSignedIn {
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
        case .componentBoard(let ref):
            ComponentReleaseBoardView(component: ref)
        default:
            BugListView(selection: workspace.sidebarSelection,
                        selectedBugID: $workspace.selectedBugID,
                        onNewBug: createDraft,
                        newBugHelp: newBugHelpText)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        #if os(macOS)
        NavigationStack(path: detailPathBinding) {
            rootDetailView
                .navigationDestination(for: DetailRoute.self) { route in
                    routeView(route)
                }
        }
        #else
        rootDetailView
            .sheet(isPresented: pushedRouteSheetBinding) {
                if let last = workspace.detailPath.last {
                    routeView(last)
                }
            }
        #endif
    }

    private var detailPathBinding: Binding<[DetailRoute]> {
        Binding(
            get: { workspace.detailPath },
            set: { workspace.detailPath = $0 }
        )
    }

    @ViewBuilder
    private func routeView(_ route: DetailRoute) -> some View {
        switch route {
        case .bug(let id):
            BugDetailView(bugID: id)
        case .revision(let id):
            RevisionDetailView(revisionID: id)
        }
    }

    private var pushedRouteSheetBinding: Binding<Bool> {
        Binding(
            get: { workspace.detailPath.isEmpty == false },
            set: { newValue in
                if !newValue { workspace.detailPath = [] }
            }
        )
    }

    @ViewBuilder
    private var rootDetailView: some View {
        if let id = workspace.activeRevisionID {
            RevisionDetailView(revisionID: id)
        } else if workspace.sidebarSelection == .allDrafts, let id = workspace.selectedDraftID {
            DraftEditorView(draftID: id)
        } else if case .review(let list) = workspace.sidebarSelection {
            EmptyStateIcon(systemName: list.systemImage)
        } else {
            BugDetailView(bugID: workspace.selectedBugID)
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if let last = workspace.detailPath.last {
            switch last {
            case .bug:
                BugInspector()
            case .revision:
                RevisionInspector()
            }
        } else if workspace.activeRevisionID != nil {
            RevisionInspector()
        } else if workspace.sidebarSelection == .allDrafts, let id = workspace.selectedDraftID {
            DraftInspector(draftID: id)
        } else {
            BugInspector()
        }
    }

    private var newBugHelpText: String {
        switch workspace.sidebarSelection {
        case .component(let ref), .componentTriage(let ref), .componentBoard(let ref):
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
        case .component(let ref), .componentTriage(let ref), .componentBoard(let ref):
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
                        workspace.navigate(to: .bug(id))
                    }
                )
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyStateIcon(systemName: "sidebar.right")
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

    private static let typeOptions: [(code: String, label: String, symbol: String)] = [
        ("defect", "Defect", "ant.fill"),
        ("enhancement", "Enhancement", "sparkles"),
        ("task", "Task", "clipboard")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            componentSection
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                typeRow
                segmentedRow(
                    label: "Priority",
                    current: draft.priority,
                    options: ["P5", "P4", "P3", "P2", "P1"]
                ) { value in
                    draft.priority = value
                    draft.updatedAt = .now
                }
                segmentedRow(
                    label: "Severity",
                    current: draft.severity,
                    options: ["S4", "S3", "S2", "S1"]
                ) { value in
                    draft.severity = value
                    draft.updatedAt = .now
                }
                assigneeRow
                keywordsRow
                whiteboardRow
                blocksRow
                datesRow
            }
            Divider()
            securitySection
        }
        .scaledFont(.callout)
        .sheet(isPresented: $showComponentPicker) {
            ComponentPickerSheet(onPick: { product, component in
                draft.product = product.name
                draft.componentName = component.name
                draft.updatedAt = .now
            })
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorSectionHeader(title: "Security")
            if draft.isConfidential {
                HStack(spacing: 8) {
                    Label("Confidential", systemImage: "lock.fill")
                        .scaledFont(.callout)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Remove") {
                        draft.isConfidential = false
                        draft.updatedAt = .now
                    }
                    .buttonStyle(.borderless)
                    .scaledFont(.caption)
                }
            } else {
                Button {
                    draft.isConfidential = true
                    draft.updatedAt = .now
                } label: {
                    Label("Confidential", systemImage: "lock")
                        .scaledFont(.callout)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var componentSection: some View {
        let isMetaSeeded = !draft.blocks.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Text("Component").foregroundStyle(.secondary).scaledFont(.caption)
            if let ref = draft.componentRef {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ref.component)
                        Text(ref.product)
                            .scaledFont(.caption)
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
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var typeRow: some View {
        GridRow {
            Text("Type").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Picker("Type", selection: Binding(
                    get: { draft.type ?? "" },
                    set: { value in
                        draft.type = value.isEmpty ? nil : value
                        draft.updatedAt = .now
                    }
                )) {
                    ForEach(Self.typeOptions, id: \.code) { option in
                        Image(systemName: option.symbol)
                            .help(option.label)
                            .accessibilityLabel(option.label)
                            .tag(option.code)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                clearButton(isVisible: draft.type != nil, label: "Type") {
                    draft.type = nil
                    draft.updatedAt = .now
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func segmentedRow(
        label: String,
        current: String?,
        options: [String],
        onPick: @escaping (String?) -> Void
    ) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Picker(label, selection: Binding(
                    get: { current ?? "" },
                    set: { value in onPick(value.isEmpty ? nil : value) }
                )) {
                    ForEach(options, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                clearButton(isVisible: current != nil && current?.isEmpty == false, label: label) {
                    onPick(nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func clearButton(isVisible: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
        .accessibilityHidden(!isVisible)
        .help("Clear \(label)")
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
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(Workspace.self) private var workspace
    @Environment(ResourceCache.self) private var cache
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    @Query(sort: [SortDescriptor(\FollowedComponent.position),
                  SortDescriptor(\FollowedComponent.addedAt)])
    private var followedComponents: [FollowedComponent]

    @Binding var selection: SidebarSelection?

    @State private var addMetaBugTarget: FollowedComponent?
    @State private var showAddComponent = false
    @State private var needsInfoCount: Int?
    @State private var triageCount: Int?

    @AppStorage("sidebar.section.review.expanded") private var reviewExpanded = true
    @AppStorage("sidebar.section.components.expanded") private var componentsExpanded = true

    var body: some View {
        List(selection: $selection) {
                Section {
                    ForEach(visibleSmartEndpoints) { endpoint in
                        if endpoint == .todo {
                            TodoSidebarRow()
                                .tag(SidebarSelection.smart(endpoint))
                        } else if endpoint == .needsReview {
                            smartEndpointRow(endpoint, count: needsInfoCount)
                                .tag(SidebarSelection.smart(endpoint))
                        } else if endpoint == .triage {
                            smartEndpointRow(endpoint, count: triageCount)
                                .tag(SidebarSelection.smart(endpoint))
                        } else {
                            smartEndpointRow(endpoint)
                                .tag(SidebarSelection.smart(endpoint))
                        }
                    }
                    Label("Drafts", systemImage: "square.and.pencil")
                    .tag(SidebarSelection.allDrafts)
                }

                Section(isExpanded: $reviewExpanded) {
                    ForEach(ReviewList.allCases) { item in
                        if item == .review {
                            Label {
                                HStack {
                                    Text(item.title)
                                    Spacer()
                                    if unseenReviewCount > 0 {
                                        UnseenReviewBadge(count: unseenReviewCount)
                                    }
                                }
                            } icon: {
                                Image(systemName: item.systemImage)
                            }
                            .tag(SidebarSelection.review(item))
                        } else {
                            Label(item.title, systemImage: item.systemImage)
                                .tag(SidebarSelection.review(item))
                        }
                    }
                } header: {
                    Text("Review")
                }

                Section(isExpanded: $componentsExpanded) {
                    ForEach(followedComponents) { followed in
                        FollowedComponentEntry(
                            followed: followed,
                            onAddMetaBug: { addMetaBugTarget = followed }
                        )
                    }
                    .onMove(perform: moveComponents)
                } header: {
                    Text("Components")
                }
            }
        .navigationTitle("Zilla Tracker")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        #else
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                accountMenu
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                accountMenu
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddComponent = true
                } label: {
                    Label("Add Component", systemImage: "plus")
                }
                .help("Add Component")
            }
        }
        .sheet(item: $addMetaBugTarget) { component in
            MetaBugPickerSheet(component: component)
        }
        .sheet(isPresented: $showAddComponent) {
            ComponentPickerSheet()
        }
        .task(id: auth.currentUser?.name) {
            if auth.isSignedIn, let login = auth.currentUser?.name {
                await workspace.loadProducts(using: auth.client)
                autoFollowOwnedComponents(for: login)
            }
        }
        .task(id: triageCountKey) {
            await loadTriageCount(force: false)
        }
        .task(id: workspace.bugListRefreshToken) {
            await loadTriageCount(force: true)
            await loadNeedsInfoCount(force: true)
        }
        .task(id: needsInfoCountKey) {
            await loadNeedsInfoCount(force: false)
        }
        .task(id: reviewBadgeKey) {
            await loadReviewBadge(force: false)
        }
        .task(id: workspace.revisionListRefreshToken) {
            await loadReviewBadge(force: true)
        }
        #if os(macOS)
        .onChange(of: unseenReviewCount, initial: true) { _, new in
            NSApplication.shared.dockTile.badgeLabel = new > 0 ? "\(new)" : nil
        }
        #endif
    }

    private func smartEndpointRow(_ endpoint: SmartEndpoint, count: Int? = nil) -> some View {
        Label {
            HStack {
                Text(endpoint.title)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: endpoint.systemImage)
        }
    }

    private var visibleSmartEndpoints: [SmartEndpoint] {
        SmartEndpoint.allCases
    }

    private var followedComponentRefs: [ComponentRef] {
        followedComponents.map(\.ref)
    }

    private struct TriageCountKey: Hashable {
        let signedIn: Bool
        let login: String?
        let componentRefs: [ComponentRef]
    }

    private var triageCountKey: TriageCountKey {
        TriageCountKey(
            signedIn: auth.isSignedIn,
            login: auth.currentUser?.name,
            componentRefs: followedComponentRefs
        )
    }

    private struct NeedsInfoCountKey: Hashable {
        let signedIn: Bool
        let login: String?
    }

    private var needsInfoCountKey: NeedsInfoCountKey {
        NeedsInfoCountKey(
            signedIn: auth.isSignedIn,
            login: auth.currentUser?.name
        )
    }

    private func countQuery(_ query: BugQuery, defaultFilter: BugStatusFilter, force: Bool) async -> Int? {
        guard auth.isSignedIn, let login = auth.currentUser?.name else { return nil }
        var countQuery = defaultFilter.apply(to: query)
        countQuery = countQuery.substitutingMe(with: login)
        return try? await cache.bugCount(countQuery, force: force, using: auth.client)
    }

    private func loadTriageCount(force: Bool) async {
        guard auth.isSignedIn, auth.currentUser?.name != nil else {
            triageCount = nil
            return
        }
        guard !followedComponentRefs.isEmpty else {
            triageCount = 0
            return
        }

        triageCount = await countQuery(.triage(in: followedComponentRefs), defaultFilter: .open, force: force)
    }

    private func autoFollowOwnedComponents(for login: String) {
        let ownedRefs = workspace.ownedComponentRefs(for: login)
        guard !ownedRefs.isEmpty else { return }

        var knownRefs = Set(followedComponents.map(\.ref))
        var nextPosition = (followedComponents.map(\.position).max() ?? -1) + 1

        for ref in ownedRefs where !knownRefs.contains(ref) {
            modelContext.insert(FollowedComponent(
                product: ref.product,
                componentName: ref.component,
                position: nextPosition
            ))
            knownRefs.insert(ref)
            nextPosition += 1
        }
    }

    private func loadNeedsInfoCount(force: Bool) async {
        guard auth.isSignedIn, auth.currentUser?.name != nil else {
            needsInfoCount = nil
            return
        }

        needsInfoCount = await countQuery(.needsReviewFromMe, defaultFilter: .all, force: force)
    }

    private var reviewQuery: RevisionQuery? {
        guard let phid = phab.currentUser?.phid else { return nil }
        return .reviewing(responsiblePHID: phid, statuses: nil)
    }

    private struct ReviewBadgeKey: Hashable {
        let signedIn: Bool
        let phid: String?
    }

    private var reviewBadgeKey: ReviewBadgeKey {
        ReviewBadgeKey(
            signedIn: phab.isSignedIn,
            phid: phab.currentUser?.phid
        )
    }

    private var unseenReviewCount: Int {
        guard let query = reviewQuery,
              let result: RevisionSearchResult = cache.get(.revisionSearch(query)) else {
            return 0
        }
        let viewerPHID = phab.currentUser?.phid
        var count = 0
        for revision in result.data {
            if revision.fields.authorPHID == viewerPHID { continue }
            if viewedRevisions.contains(revision.id) { continue }
            count += 1
        }
        return count
    }

    private func loadReviewBadge(force: Bool) async {
        guard phab.isSignedIn, let query = reviewQuery else { return }
        _ = try? await cache.revisionSearch(query, force: force, using: phab.client)
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
            Label("Triage", systemImage: SmartEndpoint.triage.systemImage)
                .tag(SidebarSelection.componentTriage(followed.ref))
            Label("Board", systemImage: "rectangle.3.group")
                .tag(SidebarSelection.componentBoard(followed.ref))
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
        Label {
            HStack {
                Text(SmartEndpoint.todo.title)
                Spacer()
                if !todoOrder.isEmpty {
                    Text("\(todoOrder.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: SmartEndpoint.todo.systemImage)
        }
            .background(
                isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .dropDestination(for: BugTransfer.self) { transfers, _ in
                var nextPosition = (todoOrder.last?.position ?? -1) + 1
                var inserted = false
                for transfer in transfers where !todoOrder.contains(where: { $0.bugId == transfer.id }) {
                    modelContext.upsertBugOrderEntry(
                        endpointKey: BugOrderEntry.todoKey,
                        bugId: transfer.id,
                        position: nextPosition
                    )
                    nextPosition += 1
                    inserted = true
                }
                return inserted
            } isTargeted: { isDropTarget = $0 }
    }
}

private struct UnseenReviewBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.blue, in: Capsule())
            .accessibilityLabel("\(count) unseen revisions waiting for review")
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

    private var isGlobalTriage: Bool {
        selection == .smart(.triage)
    }

    private var followedComponentRefs: [ComponentRef] {
        followedComponents.map(\.ref)
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
        .navigationSplitViewColumnWidth(min: 400, ideal: 560)
        #else
        .toolbarTitleDisplayMode(.inline)
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
        .help("Filter bugs")
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
        BugMilestoneMenu(bug: bug)
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
        modelContext.upsertBugOrderEntry(
            endpointKey: BugOrderEntry.todoKey,
            bugId: bugID,
            position: nextPosition
        )
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
            triageComponentRefs: isGlobalTriage ? followedComponentRefs : [],
            todoIDs: isTodo ? todoOrder.map(\.bugId) : []
        )
    }

    private var title: String {
        guard let selection else { return "Zilla Tracker" }
        switch selection {
        case .smart(let s): return s.title
        case .component(let ref): return "\(ref.product) :: \(ref.component)"
        case .componentTriage(let ref): return "\(ref.product) :: \(ref.component) Triage"
        case .componentBoard(let ref): return "\(ref.product) :: \(ref.component)"
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
        let filter = workspace.bugStatusFilter
        var query = selection == .smart(.myBugs) && filter == .reported
            ? .reportedByMe
            : (isGlobalTriage ? .triage(in: followedComponentRefs) : workspace.bugQuery(for: selection))
        query = filter.apply(to: query)
        if let login = auth.currentUser?.name {
            query = query.substitutingMe(with: login)
        }
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

        if isGlobalTriage && followedComponentRefs.isEmpty {
            bugs = []
            dependents = [:]
            totalMatches = 0
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
            if bugs != result.bugs {
                bugs = result.bugs
                dependents = [:]
            }
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
                    query = filter.apply(to: query)
                    if let login {
                        query = query.substitutingMe(with: login)
                    }
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
    let triageComponentRefs: [ComponentRef]
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

struct BugRow: View {
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
