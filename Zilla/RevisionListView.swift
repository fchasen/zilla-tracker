//
//  RevisionListView.swift
//  Zilla
//

import SwiftUI
import PhabricatorKit

struct RevisionListView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(ResourceCache.self) private var cache
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    @Environment(RevisionActivityStore.self) private var revisionActivity

    let list: RevisionList

    @State private var allRevisions: [Revision] = []
    @State private var isTruncated = false
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var lastSeenRefreshToken: UUID?
    @State private var lastSeenIdentity: LoadIdentity?

    var body: some View {
        @Bindable var workspace = workspace
        Group {
            if !phab.isSignedIn {
                signedOutPlaceholder
            } else if isLoading && allRevisions.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load revisions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else if allRevisions.isEmpty {
                ContentUnavailableView(
                    "No revisions",
                    systemImage: "tray",
                    description: Text(emptyDescription)
                )
            } else if displayedRevisions.isEmpty && !trimmedSearch.isEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
            } else if displayedRevisions.isEmpty {
                ContentUnavailableView {
                    Label("No revisions in the selected groups", systemImage: "person.2.slash")
                } description: {
                    Text("Every reviewer group is hidden by the current filter.")
                } actions: {
                    Button("Show All") { workspace.hiddenReviewerScopeIDs = [] }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: revisionSelectionBinding) {
                    ForEach(displayedRevisions) { revision in
                        RevisionRow(
                            revision: revision,
                            attentionList: attentionList,
                            viewerPHID: list == .reviews ? phab.currentUser?.phid : nil,
                            viewerProjectPHIDs: list == .reviews ? phab.viewerProjectPHIDs : []
                        )
                            .tag(Optional(revision.id))
                    }
                    if isTruncated {
                        Text("Showing the first \(RevisionPage.defaultMaxPages * RevisionQuery.pageSize) revisions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        #if os(macOS)
        .navigationTitle(list.title)
        .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        #else
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    workspace.revisionListRefreshToken = UUID()
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help("Refresh")
                .disabled(isLoading || !phab.isSignedIn)
            }
            if list == .patches {
                ToolbarItem(placement: .primaryAction) {
                    patchScopeMenu
                }
            }
            if list == .reviews, reviewerScopeEntries.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    reviewerScopeMenu
                }
            }
            if !isLandedPatches {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            }
        }
        .searchable(text: $workspace.searchText, prompt: Text(searchPrompt))
        .task(id: taskKey) {
            let current = workspace.revisionListRefreshToken
            let force = lastSeenRefreshToken != nil && lastSeenRefreshToken != current
            let identity = loadIdentity
            let identityChanged = lastSeenIdentity != nil && lastSeenIdentity != identity
            lastSeenRefreshToken = current
            lastSeenIdentity = identity
            if identityChanged {
                allRevisions = []
                isTruncated = false
                loadError = nil
            }
            await load(force: force)
            await refreshActivity()
        }
    }

    private var isLandedPatches: Bool {
        list == .patches && workspace.patchScope == .landed
    }

    private var attentionList: RevisionList? {
        isLandedPatches ? nil : list
    }

    private func refreshActivity() async {
        guard let attentionList, let viewerPHID = phab.currentUser?.phid else { return }
        let pending = allRevisions.filter {
            RevisionAttention.needsActivity($0, in: attentionList, mark: viewedRevisions.mark(for: $0.id))
        }
        await revisionActivity.refresh(pending, viewerPHID: viewerPHID, using: phab.client)
    }

    private var trimmedSearch: String {
        workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchPrompt: String {
        list == .reviews ? "Search reviews" : "Search patches"
    }

    private var displayedRevisions: [Revision] {
        var result = allRevisions
        if list == .reviews, let viewerPHID = phab.currentUser?.phid,
           !workspace.hiddenReviewerScopeIDs.isEmpty {
            let hidden = workspace.hiddenReviewerScopeIDs
            let projects = phab.viewerProjectPHIDs
            result = result.filter { revision in
                let scopes = ReviewerScope.scopes(
                    for: revision,
                    viewerPHID: viewerPHID,
                    viewerProjectPHIDs: projects
                )
                return !scopes.allSatisfy { hidden.contains($0.id) }
            }
        }
        let needle = trimmedSearch
        if !needle.isEmpty {
            result = result.filter { revisionMatches($0, search: needle) }
        }
        return result
    }

    private var reviewerScopeEntries: [(scope: ReviewerScope, title: String)] {
        guard list == .reviews, let viewerPHID = phab.currentUser?.phid else { return [] }
        return ReviewerScope.present(
            in: allRevisions,
            viewerPHID: viewerPHID,
            viewerProjectPHIDs: phab.viewerProjectPHIDs,
            name: { phab.projectName($0) }
        )
    }

    private var revisionSelectionBinding: Binding<Int?> {
        Binding(
            get: { workspace.activeRevisionID },
            set: { workspace.activeRevisionID = $0 }
        )
    }

    private var patchScopeMenu: some View {
        @Bindable var workspace = workspace
        return Menu {
            Picker(selection: $workspace.patchScope) {
                ForEach(PatchScope.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label(workspace.patchScope.title, systemImage: workspace.patchScope.systemImage)
        }
        .help("Show active or landed patches")
    }

    private var reviewerScopeMenu: some View {
        Menu {
            ForEach(reviewerScopeEntries, id: \.scope.id) { entry in
                Toggle(entry.title, isOn: reviewerScopeBinding(entry.scope))
            }
            if !workspace.hiddenReviewerScopeIDs.isEmpty {
                Divider()
                Button("Show All") { workspace.hiddenReviewerScopeIDs = [] }
            }
        } label: {
            Label("Reviewers", systemImage: workspace.hiddenReviewerScopeIDs.isEmpty
                ? "person.2"
                : "person.2.fill")
        }
        .help("Filter by reviewer group")
    }

    private func reviewerScopeBinding(_ scope: ReviewerScope) -> Binding<Bool> {
        Binding(
            get: { !workspace.hiddenReviewerScopeIDs.contains(scope.id) },
            set: { isOn in
                if isOn {
                    workspace.hiddenReviewerScopeIDs.remove(scope.id)
                } else {
                    workspace.hiddenReviewerScopeIDs.insert(scope.id)
                }
            }
        )
    }

    private var filterBinding: Binding<RevisionStatusFilter> {
        Binding(
            get: { workspace.revisionStatusFilter(for: list) },
            set: { workspace.revisionStatusFilters[list] = $0 }
        )
    }

    private var filterMenu: some View {
        Menu {
            Picker(selection: filterBinding) {
                ForEach(RevisionStatusFilter.allCases) { option in
                    Label(option.label, systemImage: option.systemImage).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: filterBinding.wrappedValue == .all
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Filter by status")
    }

    private var emptyDescription: String {
        switch list {
        case .reviews: return "No revisions waiting for your review."
        case .patches:
            switch workspace.patchScope {
            case .active: return "No open revisions you authored."
            case .landed: return "No revisions landed in the last week."
            }
        }
    }

    private var signedOutPlaceholder: some View {
        ContentUnavailableView {
            Label("Phabricator not connected", systemImage: "key")
        } description: {
            Text("Add your Phabricator API token to load revisions.")
        } actions: {
            Button("Connect Phabricator…") {
                workspace.phabricatorSettingsPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func load(force: Bool) async {
        guard phab.isSignedIn, let phid = phab.currentUser?.phid else {
            allRevisions = []
            isTruncated = false
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let filter = effectiveFilter
        let query: RevisionQuery = {
            switch list {
            case .reviews:
                return .reviewing(responsiblePHID: phid, statuses: filter.queryStatuses)
            case .patches:
                switch workspace.patchScope {
                case .active:
                    return .authored(authorPHID: phid, statuses: filter.queryStatuses)
                case .landed:
                    let cal = Calendar.current
                    let anchor = cal.dateInterval(of: .hour, for: .now)?.start ?? .now
                    let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: anchor) ?? anchor
                    return .landed(authorPHID: phid, since: oneWeekAgo)
                }
            }
        }()
        do {
            let page = try await cache.revisionSearchAllPages(query, force: force, using: phab.client)
            let next = list == .reviews
                ? page.revisions.filter { $0.fields.authorPHID != phid }
                : page.revisions
            if allRevisions != next {
                allRevisions = next
            }
            isTruncated = page.truncated
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }

    private var effectiveFilter: RevisionStatusFilter {
        isLandedPatches ? .all : workspace.revisionStatusFilter(for: list)
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(list: list, scope: list == .patches ? workspace.patchScope : .active)
    }

    private var taskKey: TaskKey {
        TaskKey(
            identity: loadIdentity,
            signedIn: phab.isSignedIn,
            refresh: workspace.revisionListRefreshToken,
            filter: effectiveFilter
        )
    }

    private struct LoadIdentity: Hashable {
        let list: RevisionList
        let scope: PatchScope
    }

    private struct TaskKey: Hashable {
        let identity: LoadIdentity
        let signedIn: Bool
        let refresh: UUID
        let filter: RevisionStatusFilter
    }
}

private struct RevisionRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    @Environment(RevisionActivityStore.self) private var revisionActivity
    @Environment(\.openURL) private var openURL
    let revision: Revision
    let attentionList: RevisionList?
    let viewerPHID: String?
    let viewerProjectPHIDs: Set<String>

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if needsAttention {
                        Circle()
                            .fill(.blue)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("New")
                    }
                    Text(revision.revisionLabel)
                        .font(.callout.weight(.semibold).monospaced())
                        .foregroundStyle(.blue)
                    if shouldShowStatusBadge {
                        StatusBadge(status: revision.fields.status)
                    }
                    if revision.fields.isDraft {
                        StatusBadge(status: RevisionStatus(value: "draft", name: "Draft", closed: false))
                    }
                }
                Text(revisionTitleAttributed(revision.fields.title))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let bug = revision.fields.bugzillaBugID, !bug.isEmpty {
                        Button {
                            if let id = Int(bug) {
                                workspace.selectedBugID = id
                            }
                        } label: {
                            Text(verbatim: "#\(bug)")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Open bug \(bug) in Zilla")
                        Text(verbatim: "·")
                    }
                    Text(revision.fields.dateModified, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenuContent }
    }

    private var needsAttention: Bool {
        guard let attentionList else { return false }
        return RevisionAttention.needsAttention(
            in: attentionList,
            mark: viewedRevisions.mark(for: revision.id),
            activity: revisionActivity.activity[revision.id]
        )
    }

    private var revisionURL: URL? {
        URL(string: "https://phabricator.services.mozilla.com/D\(revision.id)")
    }

    private var shouldShowStatusBadge: Bool {
        guard revision.fields.status.value == RevisionStatus.Value.needsReview else { return true }
        guard viewerPHID != nil else { return true }
        let entries = relevantReviewerEntries
        guard !entries.isEmpty else { return true }
        if entries.contains(where: { Self.statusStillNeedsAction($0.status) }) {
            return true
        }
        return !entries.contains(where: \.isBlocking)
    }

    private var relevantReviewerEntries: [Reviewer] {
        guard let reviewers = revision.attachments?.reviewers?.reviewers else { return [] }
        return reviewers.filter { reviewer in
            if reviewer.reviewerPHID == viewerPHID { return true }
            return viewerProjectPHIDs.contains(reviewer.reviewerPHID)
        }
    }

    private static func statusStillNeedsAction(_ status: String) -> Bool {
        switch status {
        case Reviewer.Status.accepted, Reviewer.Status.rejected, Reviewer.Status.resigned:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let url = revisionURL {
            Button("Open in Phabricator") { openURL(url) }
            Button("Copy Revision Link") {
                copyToPasteboard(url.absoluteString)
            }
        }
        Button("Copy Revision ID") {
            copyToPasteboard(revision.revisionLabel)
        }
        if attentionList != nil {
            Divider()
            if needsAttention {
                Button("Mark as Viewed") {
                    viewedRevisions.markViewed(revision.id)
                }
            } else {
                Button("Mark as Unviewed") {
                    viewedRevisions.markUnviewed(revision.id)
                }
            }
        }
        if let bug = revision.fields.bugzillaBugID, let id = Int(bug) {
            Divider()
            Button("Open Linked Bug #\(bug)") {
                workspace.selectedBugID = id
            }
        }
    }
}

