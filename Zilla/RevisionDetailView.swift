import SwiftUI
import PhabricatorKit
import Textual

struct RevisionDetailView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    @Environment(\.openURL) private var openURL

    let revisionID: Int

    @State private var actionSheet: RevisionActionSheetState?

    @State private var revisionSnapshot: Revision?
    @State private var diffSnapshot: DiffDetail?
    @State private var transactionsSnapshot: [RevisionTransaction] = []
    @State private var inlinesSnapshot: [InlineComment] = []
    @State private var stackSnapshot: RevisionStackGraph?

    #if os(iOS)
    @State private var isPresentingCommentSheet: Bool = false
    #endif

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
        .navigationTitle(Text(verbatim: "D\(workspace.loadedRevision?.id ?? revisionID)"))
        .toolbar {
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
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button {
                    isPresentingCommentSheet = true
                } label: {
                    Label("New Comment", systemImage: "square.and.pencil")
                }
                .disabled(workspace.loadedRevision == nil || !phab.isSignedIn)
            }
            #endif
        }
        .task(id: revisionID) {
            viewedRevisions.markViewed(revisionID)
            if phab.isSignedIn {
                await workspace.loadRevision(id: revisionID, using: phab.client)
                if workspace.loadedRevision?.id == revisionID {
                    revisionSnapshot = workspace.loadedRevision
                    diffSnapshot = workspace.loadedRevisionDiff
                    transactionsSnapshot = workspace.loadedRevisionTransactions
                    inlinesSnapshot = workspace.loadedRevisionInlines
                    stackSnapshot = workspace.loadedRevisionStack
                }
            }
        }
        .onAppear { restoreSnapshotIfNeeded() }
        .onChange(of: workspace.loadedRevision?.id) { _, newID in
            guard newID == revisionID else { return }
            revisionSnapshot = workspace.loadedRevision
            diffSnapshot = workspace.loadedRevisionDiff
            transactionsSnapshot = workspace.loadedRevisionTransactions
            inlinesSnapshot = workspace.loadedRevisionInlines
            stackSnapshot = workspace.loadedRevisionStack
        }
        .onChange(of: workspace.loadedRevisionStack?.focalID) { _, newFocal in
            guard newFocal == revisionID else { return }
            stackSnapshot = workspace.loadedRevisionStack
        }
        .sheet(item: $actionSheet) { state in
            RevisionActionSheet(state: state) { transactions in
                if let error = await workspace.applyRevisionEdit(transactions: transactions, using: phab.client) {
                    workspace.lastUpdateError = error.localizedDescription
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isPresentingCommentSheet) {
            RevisionCommentSheet()
        }
        #endif
        .interceptingMozillaLinks(workspace: workspace)
    }

    private func restoreSnapshotIfNeeded() {
        guard let revisionSnapshot, workspace.loadedRevision?.id != revisionSnapshot.id else { return }
        workspace.publishLoadedRevision(
            revisionSnapshot,
            diff: diffSnapshot,
            transactions: transactionsSnapshot,
            inlines: inlinesSnapshot,
            stack: stackSnapshot
        )
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
                        RemarkupText(source: summary)
                            .textSelection(.enabled)
                    }
                    if let testPlan = revision.fields.testPlan, !testPlan.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Test Plan")
                                .scaledFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            RemarkupText(source: testPlan)
                                .textSelection(.enabled)
                        }
                    }
                    Divider()
                    RevisionActivityView()
                    Divider()
                    #if os(macOS)
                    RevisionCommentComposer()
                    Divider()
                    #endif
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
