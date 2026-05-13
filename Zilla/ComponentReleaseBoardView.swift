import SwiftUI
import BugzillaKit

enum ReleaseBoardColumn: String, CaseIterable, Identifiable, Hashable {
    case unassigned
    case inProgress
    case inReview
    case inTesting
    case done
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .inTesting: return "In Testing"
        case .done: return "Done"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .unassigned: return "tray"
        case .inProgress: return "play.circle"
        case .inReview: return "eye.circle"
        case .inTesting: return "checkmark.seal"
        case .done: return "checkmark.circle"
        case .other: return "questionmark.circle"
        }
    }

    var acceptsDrops: Bool {
        self != .other
    }

    static let workflow: [ReleaseBoardColumn] = [.unassigned, .inProgress, .inReview, .inTesting, .done]
}

enum ReleaseBoardMoveError: LocalizedError, Equatable {
    case missingCurrentUser
    case missingPatch
    case invalidColumn

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return "Sign in to Bugzilla before assigning this bug."
        case .missingPatch:
            return "A bug needs an active Phabricator patch attachment before it can move to In Review."
        case .invalidColumn:
            return "This board column cannot accept drops."
        }
    }
}

enum ReleaseBoardAssigneeFilter: String, CaseIterable, Identifiable {
    case all
    case mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .mine: return "Mine"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "person.2"
        case .mine: return "person.crop.circle"
        }
    }
}

enum ReleaseBoardPlanner {
    nonisolated static let unassignedUser = "nobody@mozilla.org"

    nonisolated static func column(for bug: Bug) -> ReleaseBoardColumn {
        if isResolvedFixed(bug), hasQEVerifyPlus(bug) {
            return .inTesting
        }
        if isClosedFixed(bug) {
            return .done
        }
        if isClosed(bug.status) {
            return .other
        }
        if !isUnassigned(bug.assignedTo) {
            return bug.hasPhabricatorPatch ? .inReview : .inProgress
        }
        return .unassigned
    }

    nonisolated static func update(forMoving bug: Bug, to column: ReleaseBoardColumn, currentUser: String?) -> Result<BugUpdate, ReleaseBoardMoveError> {
        switch column {
        case .unassigned:
            return .success(BugUpdate(status: "NEW", assignedTo: unassignedUser))
        case .inProgress:
            return assignedUpdate(for: bug, status: "ASSIGNED", currentUser: currentUser)
        case .inReview:
            guard bug.hasPhabricatorPatch else { return .failure(.missingPatch) }
            return assignedUpdate(for: bug, status: "ASSIGNED", currentUser: currentUser)
        case .inTesting:
            let flag = qeVerifyFlag(in: bug)
            return .success(BugUpdate(
                status: "RESOLVED",
                resolution: "FIXED",
                flags: [
                    FlagUpdate(
                        id: flag?.id,
                        name: flag == nil ? "qe-verify" : nil,
                        status: "+"
                    )
                ]
            ))
        case .done:
            let flag = qeVerifyFlag(in: bug)
            let flags = flag?.status == "+"
                ? [FlagUpdate(id: flag?.id, status: "X")]
                : nil
            return .success(BugUpdate(status: "RESOLVED", resolution: "FIXED", flags: flags))
        case .other:
            return .failure(.invalidColumn)
        }
    }

    nonisolated static func hasQEVerifyPlus(_ bug: Bug) -> Bool {
        qeVerifyFlag(in: bug)?.status == "+"
    }

    nonisolated static func isAssigned(_ bug: Bug, to user: User?) -> Bool {
        guard let user else { return false }
        let userValues = Set([
            normalizedUserValue(user.name),
            normalizedUserValue(user.email)
        ].compactMap { $0 })
        guard !userValues.isEmpty else { return false }
        let bugValues = Set([
            normalizedUserValue(bug.assignedTo),
            normalizedUserValue(bug.assignedToDetail?.name),
            normalizedUserValue(bug.assignedToDetail?.email)
        ].compactMap { $0 })
        return !bugValues.isDisjoint(with: userValues)
    }

    private nonisolated static func assignedUpdate(for bug: Bug, status: String, currentUser: String?) -> Result<BugUpdate, ReleaseBoardMoveError> {
        if isUnassigned(bug.assignedTo) {
            guard let currentUser, !currentUser.isEmpty else { return .failure(.missingCurrentUser) }
            return .success(BugUpdate(status: status, assignedTo: currentUser))
        }
        return .success(BugUpdate(status: status))
    }

    private nonisolated static func isResolvedFixed(_ bug: Bug) -> Bool {
        bug.status.uppercased() == "RESOLVED" && bug.resolution.uppercased() == "FIXED"
    }

    private nonisolated static func isClosedFixed(_ bug: Bug) -> Bool {
        isClosed(bug.status) && bug.resolution.uppercased() == "FIXED"
    }

    private nonisolated static func isClosed(_ status: String) -> Bool {
        ["RESOLVED", "VERIFIED", "CLOSED"].contains(status.uppercased())
    }

    private nonisolated static func isUnassigned(_ assignee: String?) -> Bool {
        guard let raw = assignee?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return true }
        return raw.lowercased().contains("nobody")
    }

    private nonisolated static func qeVerifyFlag(in bug: Bug) -> Flag? {
        bug.flags.first { $0.name == "qe-verify" }
    }

    private nonisolated static func normalizedUserValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

enum ReleaseTargetMilestonePlanner {
    nonisolated static func choices(for product: Product?) -> [String] {
        guard let product else { return [] }
        let active = sortedMilestones(product.milestones.filter(\.isActive))
        let releaseTargets = active.filter { !isPlaceholderMilestone($0.name) }
        var seen: Set<String> = []
        let uniqueTargets: [String] = releaseTargets.compactMap { milestone -> String? in
            let name = milestone.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { return nil }
            seen.insert(name)
            return name
        }
        return Array(uniqueTargets.suffix(3))
    }

    nonisolated static func defaultMilestone(for product: Product?) -> String? {
        let choices = choices(for: product)
        if choices.count >= 2 {
            return choices[choices.count - 2]
        }
        return choices.first
    }

    nonisolated static func inspectorChoices(for product: Product?, current: String?) -> [String] {
        var choices = ["---"]
        let latestTargets = Self.choices(for: product)
        if let current = current?.trimmingCharacters(in: .whitespacesAndNewlines),
           !current.isEmpty,
           current != "---",
           current.caseInsensitiveCompare("Future") != .orderedSame,
           !latestTargets.contains(current) {
            choices.append(current)
        }
        choices.append(contentsOf: latestTargets)
        if !choices.contains(where: { $0.caseInsensitiveCompare("Future") == .orderedSame }) {
            choices.append("Future")
        }
        return choices
    }

    private nonisolated static func sortedMilestones(_ milestones: [ProductMilestone]) -> [ProductMilestone] {
        milestones.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey {
                return lhs.sortKey < rhs.sortKey
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private nonisolated static func isPlaceholderMilestone(_ milestone: String) -> Bool {
        let trimmed = milestone.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" || trimmed.caseInsensitiveCompare("Future") == .orderedSame
    }
}

struct BugMilestoneMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    let bug: Bug
    var onUpdated: () -> Void = {}

    var body: some View {
        Menu("Set Milestone") {
            ForEach(choices, id: \.self) { milestone in
                Button {
                    setMilestone(milestone)
                } label: {
                    if isCurrent(milestone) {
                        Label(displayName(for: milestone), systemImage: "checkmark")
                    } else {
                        Text(displayName(for: milestone))
                    }
                }
                .disabled(isCurrent(milestone))
            }
        }
        .disabled(!auth.isSignedIn)
    }

    private var choices: [String] {
        ReleaseTargetMilestonePlanner.inspectorChoices(for: product, current: bug.targetMilestone)
    }

    private var product: Product? {
        workspace.products.first { $0.name == bug.product }
    }

    private func isCurrent(_ milestone: String) -> Bool {
        normalized(bug.targetMilestone) == normalized(milestone)
    }

    private func displayName(for milestone: String) -> String {
        milestone == "---" ? "Unset" : milestone
    }

    private func normalized(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "---" : trimmed
    }

    private func setMilestone(_ milestone: String) {
        let client = auth.client
        Task {
            if let error = await workspace.applyBugUpdate(id: bug.id, BugUpdate(targetMilestone: milestone), using: client) {
                workspace.lastUpdateError = error.localizedDescription
            } else {
                workspace.bugListRefreshToken = UUID()
                onUpdated()
            }
        }
    }
}

struct ComponentReleaseBoardView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(ResourceCache.self) private var cache
    @Environment(\.openURL) private var openURL
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

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
    @State private var updatingBugIDs: Set<Bug.ID> = []
    @State private var collapsedColumns: Set<ReleaseBoardColumn> = []
    @State private var lastSeenRefreshToken: UUID?

    private static let pageLimit = 200

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
                board
            }
        }
        .navigationTitle("\(component.component) Board")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        #else
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if auth.isSignedIn {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    columnBoardButton
                }
                #endif
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
            let current = workspace.bugListRefreshToken
            let force = lastSeenRefreshToken != nil && lastSeenRefreshToken != current
            lastSeenRefreshToken = current
            await load(force: force)
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

    private var board: some View {
        List(selection: Binding(
            get: { workspace.selectedBugID },
            set: { workspace.selectedBugID = $0 }
        )) {
            ForEach(displayColumns) { column in
                releaseSection(column)
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

    #if os(macOS)
    @ViewBuilder
    private var columnBoardButton: some View {
        Button {
            openWindow(id: "component-board", value: component)
        } label: {
            Label("Column Board", systemImage: "rectangle.3.group")
        }
        .help("Open column board in a new window")
    }
    #endif

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

    @ViewBuilder
    private func releaseSection(_ column: ReleaseBoardColumn) -> some View {
        let columnBugs = groupedBugs[column] ?? []
        dropTarget(
            DisclosureGroup(isExpanded: expandedBinding(for: column)) {
                EmptyView()
            } label: {
                releaseSectionHeader(column, count: columnBugs.count)
            }
            .tint(.primary),
            column: column
        )
        .listRowSeparator(.hidden)
        if !collapsedColumns.contains(column) {
            if columnBugs.isEmpty {
                dropTarget(
                    HStack {
                        Text("No bugs")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2),
                    column: column
                )
            } else {
                ForEach(columnBugs) { bug in
                    releaseListRow(bug, in: column)
                }
            }
        }
    }

    private func expandedBinding(for column: ReleaseBoardColumn) -> Binding<Bool> {
        Binding {
            !collapsedColumns.contains(column)
        } set: { isExpanded in
            if isExpanded {
                collapsedColumns.remove(column)
            } else {
                collapsedColumns.insert(column)
            }
        }
    }

    private func releaseSectionHeader(_ column: ReleaseBoardColumn, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: column.systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .imageScale(.medium)
                .frame(width: 20)
            Text(column.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func releaseListRow(_ bug: Bug, in column: ReleaseBoardColumn) -> some View {
        dropTarget(
            BugRow(bug: bug)
                .tag(Optional(bug.id))
                .opacity(updatingBugIDs.contains(bug.id) ? 0.55 : 1)
                .draggable(BugTransfer(id: bug.id, summary: bug.summary)) {
                    Label("#\(bug.id) \(bug.summary)", systemImage: "ant")
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .contextMenu {
                    releaseRowActions(for: bug)
                },
            column: column
        )
    }

    @ViewBuilder
    private func releaseRowActions(for bug: Bug) -> some View {
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
    }

    @ViewBuilder
    private func dropTarget<Content: View>(_ content: Content, column: ReleaseBoardColumn) -> some View {
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

    private var milestoneChoices: [String] {
        ReleaseTargetMilestonePlanner.choices(for: product)
    }

    private var product: Product? {
        workspace.products.first { $0.name == component.product }
    }

    private var filteredBugs: [Bug] {
        guard assigneeFilter == .mine else { return bugs }
        return bugs.filter { ReleaseBoardPlanner.isAssigned($0, to: auth.currentUser) }
    }

    private var hasMineBugs: Bool {
        bugs.contains { ReleaseBoardPlanner.isAssigned($0, to: auth.currentUser) }
    }

    private var defaultMilestone: String? {
        ReleaseTargetMilestonePlanner.defaultMilestone(for: product)
    }

    private func selectDefaultMilestoneIfNeeded() {
        if selectedMilestone.isEmpty || !milestoneChoices.contains(selectedMilestone) {
            selectedMilestone = defaultMilestone ?? milestoneChoices.first ?? ""
        }
    }

    private var loadKey: ComponentReleaseBoardLoadKey {
        ComponentReleaseBoardLoadKey(
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

    private func load(force: Bool) async {
        guard auth.isSignedIn, let query = makeQuery(offset: 0) else {
            bugs = []
            totalMatches = nil
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
            let result = try await cache.bugList(query, force: force, using: auth.client)
            bugs = result.bugs
            totalMatches = result.totalMatches
            canLoadMore = hasMore(loaded: result.bugs.count, fetched: result.bugs.count, total: result.totalMatches)
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
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            canLoadMore = false
        }
    }

    private func handleDrop(_ transfers: [BugTransfer], to column: ReleaseBoardColumn) -> Bool {
        guard column.acceptsDrops,
              let transfer = transfers.first,
              let bug = bugs.first(where: { $0.id == transfer.id }) else { return false }
        if ReleaseBoardPlanner.column(for: bug) == column {
            return true
        }
        switch ReleaseBoardPlanner.update(forMoving: bug, to: column, currentUser: auth.currentUser?.name) {
        case .failure(let error):
            updateError = error.localizedDescription
            return false
        case .success(let update):
            updatingBugIDs.insert(bug.id)
            Task {
                if let error = await workspace.applyBugUpdate(id: bug.id, update, using: auth.client) {
                    updateError = error.localizedDescription
                } else {
                    await load(force: true)
                }
                updatingBugIDs.remove(bug.id)
            }
            return true
        }
    }

    private func hasMore(loaded: Int, fetched: Int, total: Int?) -> Bool {
        if let total { return loaded < total }
        return fetched == Self.pageLimit
    }
}

private struct ComponentReleaseBoardLoadKey: Hashable {
    let component: ComponentRef
    let milestone: String
    let refresh: UUID
    let signedIn: Bool
}
