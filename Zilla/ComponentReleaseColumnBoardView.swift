import SwiftUI
import BugzillaKit

struct ComponentReleaseColumnBoardView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(ResourceCache.self) private var cache
    @Environment(\.openURL) private var openURL

    let component: ComponentRef

    @State private var selectedMilestone = ""
    @State private var bugs: [Bug] = []
    @State private var assigneeFilter: ReleaseBoardAssigneeFilter = .all
    @State private var totalMatches: Int?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var loadError: String?
    @State private var updateError: String?
    @State private var inspectedBugID: Bug.ID?
    @State private var isInspectorPresented = false
    @State private var lastSeenRefreshToken: UUID?
    @State private var activeLoadKey: ComponentReleaseColumnBoardLoadKey?

    private static let pageLimit = 200
    private static let boardPadding: CGFloat = 16
    private static let columnSpacing: CGFloat = 12
    private static let minimumColumnWidth: CGFloat = 180

    var body: some View {
        Group {
            if !auth.isSignedIn {
                signedOutPlaceholder
            } else if workspace.isLoadingProducts && milestoneChoices.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if milestoneChoices.isEmpty {
                ContentUnavailableView(
                    "No release targets",
                    systemImage: "target",
                    description: Text("This product has no active milestones.")
                )
            } else if isLoading && bugs.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load board",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else {
                columnBoard
            }
        }
        .navigationTitle("\(component.component) Board")
        .toolbar {
            if auth.isSignedIn {
                if hasMineBugs {
                    ToolbarItem(placement: .primaryAction) {
                        assigneeFilterMenu
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    milestoneMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    refreshButton
                }
                ToolbarItem(placement: .primaryAction) {
                    inspectorButton
                }
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            BoardBugInspector(bugID: inspectedBugID)
                .inspectorColumnWidth(min: 360, ideal: 480, max: 620)
        }
        .alert(
            "Couldn't update bug",
            isPresented: Binding(
                get: { updateError != nil },
                set: { if !$0 { updateError = nil } }
            ),
            actions: { Button("OK") { updateError = nil } },
            message: { Text(updateError ?? "") }
        )
        .task(id: auth.currentUser?.name) {
            if auth.isSignedIn {
                await workspace.loadProducts(using: auth.client)
                selectDefaultMilestoneIfNeeded()
            }
        }
        .onChange(of: milestoneChoices, initial: true) { _, _ in
            selectDefaultMilestoneIfNeeded()
        }
        .onChange(of: hasMineBugs, initial: true) { _, hasMineBugs in
            if !hasMineBugs, assigneeFilter == .mine {
                assigneeFilter = .all
            }
        }
        .task(id: loadKey) {
            let key = loadKey
            activeLoadKey = key
            let current = workspace.bugListRefreshToken
            let force = lastSeenRefreshToken != nil && lastSeenRefreshToken != current
            lastSeenRefreshToken = current
            await load(force: force, key: key)
        }
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

    private var columnBoard: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let columns = displayColumns
                let columnWidth = columnWidth(in: proxy.size.width, columnCount: columns.count)
                let columnHeight = max(220, proxy.size.height - Self.boardPadding * 2)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Self.columnSpacing) {
                        ForEach(columns) { column in
                            releaseColumn(column, width: columnWidth, height: columnHeight)
                        }
                    }
                    .padding(Self.boardPadding)
                    .frame(minWidth: proxy.size.width, alignment: .topLeading)
                }
            }
            if canLoadMore {
                Divider()
                Button {
                    Task { await loadMore() }
                } label: {
                    if isLoadingMore {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Load More", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 8)
                .disabled(isLoadingMore)
            }
        }
    }

    private var assigneeFilterMenu: some View {
        Menu {
            Picker("Board Scope", selection: $assigneeFilter) {
                ForEach(ReleaseBoardAssigneeFilter.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(assigneeFilter.title, systemImage: assigneeFilter.systemImage)
        }
        .help("Filter by assignee")
    }

    private var milestoneMenu: some View {
        Menu {
            Picker("Release Target", selection: $selectedMilestone) {
                ForEach(milestoneChoices, id: \.self) { milestone in
                    Text(milestone).tag(milestone)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(selectedMilestone.isEmpty ? "Release Target" : selectedMilestone, systemImage: "target")
        }
        .help("Release target")
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

    private var inspectorButton: some View {
        Button {
            isInspectorPresented.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.right")
        }
        .help(isInspectorPresented ? "Hide Inspector" : "Show Inspector")
    }

    @ViewBuilder
    private func releaseColumn(_ column: ReleaseBoardColumn, width: CGFloat, height: CGFloat) -> some View {
        let columnBugs = groupedBugs[column] ?? []
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(column.title, systemImage: column.systemImage)
                    .font(.headline)
                Spacer()
                Text("\(columnBugs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if columnBugs.isEmpty {
                        Text("No bugs")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(columnBugs) { bug in
                            ReleaseColumnBoardCard(
                                bug: bug,
                                isUpdating: workspace.isUpdatingBug(id: bug.id),
                                isSelected: inspectedBugID == bug.id,
                                onOpen: { inspectBug(bug.id) },
                                onOpenBugzilla: {
                                    if let url = URL(string: "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bug.id)") {
                                        openURL(url)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 2)
            }
        }
        .padding(10)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

        if column.acceptsDrops {
            content.dropDestination(for: BugTransfer.self) { transfers, _ in
                handleDrop(transfers, to: column)
            } isTargeted: { _ in }
        } else {
            content
        }
    }

    private var groupedBugs: [ReleaseBoardColumn: [Bug]] {
        Dictionary(grouping: filteredBugs, by: ReleaseBoardPlanner.column(for:))
    }

    private var displayColumns: [ReleaseBoardColumn] {
        var columns = ReleaseBoardColumn.workflow
        if groupedBugs[.other]?.isEmpty == false {
            columns.append(.other)
        }
        return columns
    }

    private var displayedBugs: [Bug] {
        bugs.map(workspace.displayedBug)
    }

    private var filteredBugs: [Bug] {
        guard assigneeFilter == .mine else { return displayedBugs }
        return displayedBugs.filter { ReleaseBoardPlanner.isAssigned($0, to: auth.currentUser) }
    }

    private var hasMineBugs: Bool {
        displayedBugs.contains { ReleaseBoardPlanner.isAssigned($0, to: auth.currentUser) }
    }

    private var milestoneChoices: [String] {
        ReleaseTargetMilestonePlanner.choices(for: product)
    }

    private var product: Product? {
        workspace.products.first { $0.name == component.product }
    }

    private var defaultMilestone: String? {
        ReleaseTargetMilestonePlanner.defaultMilestone(for: product)
    }

    private func selectDefaultMilestoneIfNeeded() {
        if selectedMilestone.isEmpty || !milestoneChoices.contains(selectedMilestone) {
            selectedMilestone = defaultMilestone ?? milestoneChoices.first ?? ""
        }
    }

    private func columnWidth(in totalWidth: CGFloat, columnCount: Int) -> CGFloat {
        let count = max(columnCount, 1)
        let spacing = Self.columnSpacing * CGFloat(max(count - 1, 0))
        let available = totalWidth - Self.boardPadding * 2 - spacing
        return max(Self.minimumColumnWidth, available / CGFloat(count))
    }

    private func inspectBug(_ id: Bug.ID) {
        inspectedBugID = id
        isInspectorPresented = true
    }

    private var loadKey: ComponentReleaseColumnBoardLoadKey {
        ComponentReleaseColumnBoardLoadKey(
            component: component,
            milestone: selectedMilestone,
            refresh: workspace.bugListRefreshToken,
            signedIn: auth.isSignedIn
        )
    }

    private static let bugIncludeFields = [
        "id", "summary", "status", "resolution", "product", "component",
        "assigned_to", "assigned_to_detail", "priority", "severity", "keywords", "type",
        "last_change_time", "creation_time", "target_milestone", "cf_rank",
        "flags.id", "flags.name", "flags.status",
        "attachments.id", "attachments.content_type", "attachments.is_obsolete"
    ]

    private func makeQuery(offset: Int) -> BugQuery? {
        guard !selectedMilestone.isEmpty else { return nil }
        return BugQuery(
            product: [component.product],
            component: [component.component],
            targetMilestone: [selectedMilestone],
            limit: Self.pageLimit,
            offset: offset,
            order: "cf_rank,bug_id",
            includeFields: Self.bugIncludeFields
        )
    }

    private func isCurrent(_ key: ComponentReleaseColumnBoardLoadKey) -> Bool {
        !Task.isCancelled && activeLoadKey == key
    }

    private func endLoading(_ key: ComponentReleaseColumnBoardLoadKey) {
        guard activeLoadKey == key else { return }
        isLoading = false
    }

    private func load(force: Bool, key: ComponentReleaseColumnBoardLoadKey) async {
        guard auth.isSignedIn, let query = makeQuery(offset: 0) else {
            bugs = []
            totalMatches = nil
            canLoadMore = false
            loadError = nil
            endLoading(key)
            return
        }

        isLoading = true
        loadError = nil
        defer { endLoading(key) }

        do {
            let result = try await cache.bugList(query, force: force, using: auth.client)
            guard isCurrent(key) else { return }
            bugs = result.bugs
            totalMatches = result.totalMatches
            canLoadMore = hasMore(loaded: result.bugs.count, fetched: result.bugs.count, total: result.totalMatches)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(key) else { return }
            loadError = error.localizedDescription
            bugs = []
            totalMatches = nil
            canLoadMore = false
        }
    }

    private func loadMore() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        guard let key = activeLoadKey else { return }
        guard let query = makeQuery(offset: bugs.count) else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await auth.client.searchBugs(query)
            guard isCurrent(key) else { return }
            let existing = Set(bugs.map(\.id))
            let appended = result.bugs.filter { !existing.contains($0.id) }
            bugs.append(contentsOf: appended)
            if let total = result.totalMatches { totalMatches = total }
            canLoadMore = hasMore(loaded: bugs.count, fetched: result.bugs.count, total: result.totalMatches ?? totalMatches)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(key) else { return }
            loadError = error.localizedDescription
            canLoadMore = false
        }
    }

    private func handleDrop(_ transfers: [BugTransfer], to column: ReleaseBoardColumn) -> Bool {
        guard column.acceptsDrops,
              let transfer = transfers.first,
              let bug = displayedBugs.first(where: { $0.id == transfer.id }) else { return false }
        if ReleaseBoardPlanner.column(for: bug) == column {
            return true
        }
        switch ReleaseBoardPlanner.update(forMoving: bug, to: column, currentUser: auth.currentUser?.name) {
        case .failure(let error):
            updateError = error.localizedDescription
            return false
        case .success(let update):
            let users = auth.currentUser.map { [$0] } ?? []
            Task {
                if let error = await workspace.applyBugUpdate(id: bug.id, update, users: users, using: auth.client) {
                    updateError = error.localizedDescription
                } else if let key = activeLoadKey {
                    await load(force: true, key: key)
                }
            }
            return true
        }
    }

    private func hasMore(loaded: Int, fetched: Int, total: Int?) -> Bool {
        if let total { return loaded < total }
        return fetched == Self.pageLimit
    }
}

private struct BoardBugInspector: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(ViewedBugsStore.self) private var viewedBugs

    let bugID: Bug.ID?

    @State private var composerErrors: [Bug.ID: String] = [:]
    @State private var updateError: String?

    private var composerTextBinding: Binding<String> {
        Binding(
            get: { bugID.flatMap { workspace.bugCommentDrafts[$0] } ?? "" },
            set: { newValue in
                guard let id = bugID else { return }
                if newValue.isEmpty {
                    workspace.bugCommentDrafts.removeValue(forKey: id)
                } else {
                    workspace.bugCommentDrafts[id] = newValue
                }
            }
        )
    }

    private var bug: Bug? { bugID.flatMap { workspace.bug(id: $0) } }
    private var comments: [Comment] { bugID.map { workspace.comments(bugID: $0) } ?? [] }
    private var loadError: String? { bugID.flatMap { workspace.bugLoadError(id: $0) } }
    private var isLoading: Bool { bugID.map { workspace.isLoadingBug(id: $0) } ?? false }

    private var composerError: String? {
        bugID.flatMap { composerErrors[$0] }
    }

    var body: some View {
        Group {
            if bugID == nil {
                ContentUnavailableView(
                    "No bug selected",
                    systemImage: "sidebar.right",
                    description: Text("Select a board card.")
                )
            } else if let error = loadError, bug == nil {
                ContentUnavailableView(
                    "Couldn't load bug",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else if let bug {
                BugContent(
                    bug: bug,
                    comments: comments,
                    loadError: loadError,
                    composerText: composerTextBinding,
                    composerError: composerError,
                    onPost: { Task { await postComment() } },
                    onUpdate: { update in Task { await applyUpdate(update) } }
                )
            } else if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .alert(
            "Couldn't update bug",
            isPresented: Binding(
                get: { updateError != nil },
                set: { if !$0 { updateError = nil } }
            ),
            actions: { Button("OK") { updateError = nil } },
            message: { Text(updateError ?? "") }
        )
        .task(id: bugID) {
            guard let bugID else { return }
            composerErrors.removeValue(forKey: bugID)
            viewedBugs.markViewed(bugID)
            await workspace.presentBug(id: bugID, using: auth.client)
        }
        .onAppear {
            if let bugID { workspace.seedBugFromCache(id: bugID) }
        }
    }

    private func applyUpdate(_ update: BugUpdate) async {
        guard let bugID else { return }
        if let error = await workspace.applyBugUpdate(id: bugID, update, using: auth.client) {
            updateError = error.localizedDescription
        } else {
            workspace.bugListRefreshToken = UUID()
        }
    }

    private func postComment() async {
        guard let bugID else { return }
        composerErrors.removeValue(forKey: bugID)
        if let error = await workspace.postComment(
            bugID: bugID,
            text: workspace.bugCommentDrafts[bugID] ?? "",
            author: auth.currentUser?.name ?? "",
            using: auth.client
        ) {
            composerErrors[bugID] = error.localizedDescription
        }
    }
}

private struct ComponentReleaseColumnBoardLoadKey: Hashable {
    let component: ComponentRef
    let milestone: String
    let refresh: UUID
    let signedIn: Bool
}

private struct ReleaseColumnBoardCard: View {
    let bug: Bug
    let isUpdating: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onOpenBugzilla: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    BugTypePill(type: bug.type, isMeta: bug.isMeta)
                    Text(FollowedMetaBug.cleanedSummary(bug.summary))
                        .font(.callout)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    Text(verbatim: "#\(bug.id)")
                    if let priority = displayPriority {
                        Text(verbatim: "·")
                        Text(priority)
                    }
                    if let assignee = displayAssignee {
                        Text(verbatim: "·")
                        Text(assignee)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .draggable(BugTransfer(id: bug.id, summary: bug.summary)) {
            Label("#\(bug.id) \(bug.summary)", systemImage: "ant")
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .contextMenu {
            Button("Open in Bugzilla") {
                onOpenBugzilla()
            }
            Button("Copy Bug Link") {
                copyToPasteboard("https://bugzilla.mozilla.org/show_bug.cgi?id=\(bug.id)")
            }
            Button("Copy Bug ID") {
                copyToPasteboard(String(bug.id))
            }
            BugMilestoneMenu(bug: bug)
        }
    }

    private var displayPriority: String? {
        guard let value = bug.priority, !value.isEmpty, value != "--" else { return nil }
        return value
    }

    private var displayAssignee: String? {
        guard !BugStatuses.isUnassigned(bug.assignedTo) else { return nil }
        return User.displayName(for: bug.assignedTo, detail: bug.assignedToDetail)
    }
}
