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

    let list: ReviewList

    @State private var revisions: [Revision] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var lastSeenRefreshToken: UUID?

    var body: some View {
        @Bindable var workspace = workspace
        Group {
            if !phab.isSignedIn {
                signedOutPlaceholder
            } else if isLoading && revisions.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load revisions",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else if revisions.isEmpty {
                ContentUnavailableView(
                    "No revisions",
                    systemImage: "tray",
                    description: Text(emptyDescription)
                )
            } else {
                List(selection: revisionSelectionBinding) {
                    ForEach(revisions) { revision in
                        RevisionRow(
                            revision: revision,
                            showsUnseenIndicator: list == .review,
                            viewerPHID: list == .review ? phab.currentUser?.phid : nil,
                            viewerProjectPHIDs: list == .review ? phab.viewerProjectPHIDs : []
                        )
                            .tag(Optional(revision.id))
                    }
                }
            }
        }
        .navigationTitle(list.title)
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 360, ideal: 460)
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
        }
        .task(id: TaskKey(list: list, signedIn: phab.isSignedIn, refresh: workspace.revisionListRefreshToken)) {
            let current = workspace.revisionListRefreshToken
            let force = lastSeenRefreshToken != nil && lastSeenRefreshToken != current
            lastSeenRefreshToken = current
            await load(force: force)
        }
        .onChange(of: list) { _, _ in
            revisions = []
            loadError = nil
        }
    }

    private var revisionSelectionBinding: Binding<Int?> {
        Binding(
            get: { workspace.activeRevisionID },
            set: { workspace.activeRevisionID = $0 }
        )
    }

    private var emptyDescription: String {
        switch list {
        case .active: return "No open revisions you authored."
        case .review: return "No revisions waiting for your review."
        case .landed: return "No revisions landed in the last week."
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
            revisions = []
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let query: RevisionQuery = {
            switch list {
            case .active: return .active(authorPHID: phid)
            case .review: return .reviewing(responsiblePHID: phid)
            case .landed:
                let cal = Calendar.current
                let anchor = cal.dateInterval(of: .hour, for: .now)?.start ?? .now
                let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: anchor) ?? anchor
                return .landed(authorPHID: phid, since: oneWeekAgo)
            }
        }()
        do {
            let result = try await cache.revisionSearch(query, force: force, using: phab.client)
            let next = list == .review
                ? result.data.filter { $0.fields.authorPHID != phid }
                : result.data
            if revisions != next {
                revisions = next
            }
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }

    private struct TaskKey: Hashable {
        let list: ReviewList
        let signedIn: Bool
        let refresh: UUID
    }
}

private struct RevisionRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    @Environment(\.openURL) private var openURL
    let revision: Revision
    let showsUnseenIndicator: Bool
    let viewerPHID: String?
    let viewerProjectPHIDs: Set<String>

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if showsUnseenIndicator && !viewedRevisions.contains(revision.id) {
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
        Divider()
        if viewedRevisions.contains(revision.id) {
            Button("Mark as Unviewed") {
                viewedRevisions.markUnviewed(revision.id)
            }
        } else {
            Button("Mark as Viewed") {
                viewedRevisions.markViewed(revision.id)
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

