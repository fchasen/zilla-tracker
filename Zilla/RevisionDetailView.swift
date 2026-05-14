import SwiftUI
import PhabricatorKit
import Textual

struct RevisionDetailView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(ViewedRevisionsStore.self) private var viewedRevisions
    @Environment(\.openExternalURL) private var openExternalURL

    let revisionID: Int

    @State private var actionSheet: RevisionActionSheetState?

    #if os(iOS)
    @State private var isPresentingCommentSheet: Bool = false
    #endif

    private var revision: Revision? {
        workspace.loadedRevision?.id == revisionID ? workspace.loadedRevision : nil
    }

    private var revisionLoadError: String? {
        revision == nil ? workspace.revisionLoadError : nil
    }

    private var isLoadingRevision: Bool {
        workspace.isLoadingRevision && revision == nil
    }

    var body: some View {
        @Bindable var workspace = workspace
        Group {
            if isLoadingRevision {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = revisionLoadError {
                ContentUnavailableView(
                    "Couldn't load revision",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else if let revision {
                content(for: revision)
            } else {
                ContentUnavailableView(
                    "Revision not loaded",
                    systemImage: "doc.text",
                    description: Text("Try refreshing or opening from the list.")
                )
            }
        }
        .navigationTitle(Text(verbatim: "D\(revision?.id ?? revisionID)"))
        .toolbar {
            if let revision, phab.isSignedIn {
                ToolbarItem(placement: .primaryAction) {
                    RevisionActionsMenu(revision: revision) { state in
                        actionSheet = state
                    }
                    .disabled(workspace.isUpdatingRevision)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let revision, isAuthor(revision) {
                    Button {
                        openExternalURL(landoURL(for: revision))
                    } label: {
                        Label("Lando", systemImage: "bird")
                    }
                    .help("Open D\(String(revision.id)) in Lando")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let revision, let url = revision.fields.uri {
                    Button {
                        openExternalURL(url)
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
                .disabled(revision == nil || !phab.isSignedIn)
            }
            #endif
        }
        .task(id: revisionID) {
            viewedRevisions.markViewed(revisionID)
            if phab.isSignedIn {
                await workspace.loadRevision(id: revisionID, using: phab.client)
            }
        }
        .onAppear { restoreCachedRevisionIfNeeded() }
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

    private func restoreCachedRevisionIfNeeded() {
        guard workspace.loadedRevision?.id != revisionID else { return }
        _ = workspace.restoreCachedRevision(id: revisionID)
    }

    private func isAuthor(_ revision: Revision) -> Bool {
        guard let myPHID = phab.currentUser?.phid else { return false }
        return revision.fields.authorPHID == myPHID
    }

    private func landoURL(for revision: Revision) -> URL {
        URL(string: "https://lando.moz.tools/D\(revision.id)/")!
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
