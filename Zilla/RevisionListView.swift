//
//  RevisionListView.swift
//  Zilla
//

import SwiftUI
import PhabricatorKit

struct RevisionListView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab

    let list: ReviewList

    @State private var revisions: [Revision] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

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
                        RevisionRow(revision: revision, showsUnseenIndicator: list == .review)
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
                    Task { await load() }
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
        .task(id: TaskKey(list: list, signedIn: phab.isSignedIn, tick: workspace.revisionListRefreshToken)) {
            await load()
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

    private func load() async {
        guard phab.isSignedIn, let phid = phab.currentUser?.phid else {
            revisions = []
            return
        }
        revisions = []
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let query: RevisionQuery = {
            switch list {
            case .active: return .active(authorPHID: phid)
            case .review: return .reviewing(responsiblePHID: phid)
            case .landed:
                let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
                return .landed(authorPHID: phid, since: oneWeekAgo)
            }
        }()
        do {
            let result = try await phab.client.searchRevisions(query)
            if list == .review {
                revisions = result.data.filter { $0.fields.authorPHID != phid }
            } else {
                revisions = result.data
            }
        } catch is CancellationError {
            return
        } catch {
            revisions = []
            loadError = error.localizedDescription
        }
    }

    private struct TaskKey: Hashable {
        let list: ReviewList
        let signedIn: Bool
        let tick: UUID
    }
}

private struct RevisionRow: View {
    @Environment(Workspace.self) private var workspace
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    let revision: Revision
    let showsUnseenIndicator: Bool

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
                    StatusBadge(status: revision.fields.status)
                    if revision.fields.isDraft {
                        StatusBadge(status: RevisionStatus(value: "draft", name: "Draft", closed: false))
                    }
                }
                Text(revision.fields.title)
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
    }
}

private struct StatusBadge: View {
    let status: RevisionStatus

    var body: some View {
        Text(status.name)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status.value {
        case RevisionStatus.Value.needsReview: return .orange
        case RevisionStatus.Value.needsRevision: return .red
        case RevisionStatus.Value.accepted: return .green
        case RevisionStatus.Value.changesPlanned: return .yellow
        case RevisionStatus.Value.draft: return .gray
        case RevisionStatus.Value.published: return .blue
        case RevisionStatus.Value.abandoned: return .secondary
        default: return .secondary
        }
    }
}
