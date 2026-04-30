import SwiftUI
import PhabricatorKit
import Textual

struct RevisionDetailView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    @Environment(\.openURL) private var openURL

    let revisionID: Int
    let onClose: () -> Void

    @State private var actionSheet: RevisionActionSheetState?

    var body: some View {
        @Bindable var workspace = workspace
        Group {
            if workspace.isLoadingRevision && workspace.loadedRevision == nil {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = workspace.revisionLoadError, workspace.loadedRevision == nil {
                ContentUnavailableView(
                    "Couldn't load revision",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else if let revision = workspace.loadedRevision {
                content(for: revision)
            } else {
                ContentUnavailableView(
                    "Revision not loaded",
                    systemImage: "doc.text",
                    description: Text("Try refreshing or opening from the list.")
                )
            }
        }
        .navigationTitle(workspace.loadedRevision.map { "D\($0.id)" } ?? "D\(revisionID)")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onClose) {
                    Label("Back", systemImage: "chevron.backward")
                }
                .help("Return to bug")
            }
            if let revision = workspace.loadedRevision, phab.isSignedIn {
                ToolbarItem(placement: .primaryAction) {
                    RevisionActionsMenu(revision: revision) { state in
                        actionSheet = state
                    }
                    .disabled(workspace.isUpdatingRevision)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let revision = workspace.loadedRevision, let url = revision.fields.uri {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open in Browser", systemImage: "arrow.up.right.square")
                    }
                    .help("Open D\(String(revision.id)) in your browser")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    workspace.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle inspector")
            }
        }
        .task(id: revisionID) {
            viewedRevisions.markViewed(revisionID)
            if phab.isSignedIn {
                await workspace.loadRevision(id: revisionID, using: phab.client)
            }
        }
        .onDisappear {
            workspace.clearLoadedRevision()
        }
        .sheet(item: $actionSheet) { state in
            RevisionActionSheet(state: state) { transactions in
                if let error = await workspace.applyRevisionEdit(transactions: transactions, using: phab.client) {
                    workspace.lastUpdateError = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func content(for revision: Revision) -> some View {
        @Bindable var workspace = workspace
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RevisionHeader(revision: revision)
                    if let summary = revision.fields.summary, !summary.isEmpty {
                        Divider()
                        StructuredText(markdown: summary)
                            .textSelection(.enabled)
                    }
                    Divider()
                    RevisionActivityView()
                    Divider()
                    RevisionCommentComposer()
                    Divider()
                    RevisionDiffView()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: workspace.pendingScrollToFile) { _, newValue in
                guard let path = newValue else { return }
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo(scrollAnchor(for: path), anchor: .top)
                }
                workspace.pendingScrollToFile = nil
            }
        }
    }

    static func scrollAnchor(for path: String) -> String { "changeset-\(path)" }
    private func scrollAnchor(for path: String) -> String { Self.scrollAnchor(for: path) }
}
