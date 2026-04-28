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

// MARK: - Drag payload

struct BugTransfer: Codable, Transferable {
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myBugs: return "My Bugs"
        case .reported: return "Reported"
        case .needsReview: return "Needs Review"
        case .recentlyChanged: return "Recently Changed"
        }
    }

    var systemImage: String {
        switch self {
        case .myBugs: return "person.crop.circle"
        case .reported: return "tray.and.arrow.up"
        case .needsReview: return "flag"
        case .recentlyChanged: return "clock"
        }
    }
}

enum SidebarSelection: Hashable {
    case smart(SmartEndpoint)
    case component(ComponentRef)
    case metaBug(Int)
}

enum BugListSort: String, CaseIterable, Identifiable, Hashable {
    case newest, recent, oldest, priority

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest"
        case .recent: return "Recent"
        case .oldest: return "Oldest"
        case .priority: return "Priority"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: return "arrow.down.circle"
        case .recent: return "clock"
        case .oldest: return "arrow.up.circle"
        case .priority: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Workspace

@Observable
final class Workspace {
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?

    var sidebarSelection: SidebarSelection? = .smart(.myBugs)
    var selectedBugID: Bug.ID?
    var searchText: String = ""
    var bugListSort: BugListSort = .newest

    func loadProducts(using client: BugzillaClient) async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        loadError = nil
        defer { isLoadingProducts = false }
        do {
            let fetched = try await client.selectableProducts()
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
        searchText = ""
    }

    func bugQuery(for selection: SidebarSelection) -> BugQuery {
        switch selection {
        case .smart(.myBugs):
            return .myOpenBugs
        case .smart(.reported):
            return .reportedByMe
        case .smart(.needsReview):
            return .needsReviewFromMe
        case .smart(.recentlyChanged):
            return .recentlyChanged(involving: BugQuery.me)
        case .component(let ref):
            return .openIn(component: ref)
        case .metaBug(let id):
            return .blockedBy(metaBug: id)
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

    @State private var showAddComponent = false

    var body: some View {
        @Bindable var workspace = workspace

        NavigationSplitView {
            Sidebar(selection: $workspace.sidebarSelection)
        } content: {
            BugListView(selection: workspace.sidebarSelection,
                        selectedBugID: $workspace.selectedBugID)
                .searchable(text: $workspace.searchText, prompt: "Search bugs")
        } detail: {
            BugDetailView(bugID: workspace.selectedBugID)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showAddComponent = true
                } label: {
                    Label("Add Component", systemImage: "plus")
                }
                .help("Add Component")
            }
            ToolbarItem(placement: .navigation) {
                Menu {
                    if let user = auth.currentUser {
                        Text(user.realName ?? user.name)
                        if let nick = user.nick {
                            Text("@\(nick)")
                        }
                        Divider()
                    }
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await auth.signOut()
                            workspace.reset()
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .help("Account")
            }
        }
        .sheet(isPresented: $showAddComponent) {
            ComponentPickerSheet()
        }
        .task {
            if workspace.products.isEmpty {
                await workspace.loadProducts(using: auth.client)
            }
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\FollowedComponent.position),
                  SortDescriptor(\FollowedComponent.addedAt)])
    private var followedComponents: [FollowedComponent]

    @Binding var selection: SidebarSelection?

    @State private var addMetaBugTarget: FollowedComponent?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SmartEndpoint.allCases) { endpoint in
                    Label(endpoint.title, systemImage: endpoint.systemImage)
                        .tag(SidebarSelection.smart(endpoint))
                }
            }

            Section("Components") {
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
            }
        }
        .navigationTitle("Zilla")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        #endif
        .sheet(item: $addMetaBugTarget) { component in
            MetaBugPickerSheet(component: component)
        }
    }

    private func moveComponents(from source: IndexSet, to destination: Int) {
        var items = followedComponents
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.position = index
        }
    }
}

private struct FollowedComponentEntry: View {
    @Environment(\.modelContext) private var modelContext
    let followed: FollowedComponent
    let onAddMetaBug: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        let metas = followed.metaBugs.sorted {
            ($0.position, $0.addedAt) < ($1.position, $1.addedAt)
        }

        Group {
            if metas.isEmpty {
                FollowedComponentRow(followed: followed)
                    .tag(SidebarSelection.component(followed.ref))
            } else {
                DisclosureGroup {
                    ForEach(metas) { meta in
                        FollowedMetaBugRow(meta: meta)
                            .tag(SidebarSelection.metaBug(meta.bugId))
                            .contextMenu {
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
                        .tag(SidebarSelection.component(followed.ref))
                }
            }
        }
        .background(
            isDropTarget
                ? Color.accentColor.opacity(0.18)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contextMenu {
            Button("Add Meta Bug…") { onAddMetaBug() }
            Divider()
            Button("Remove", role: .destructive) {
                modelContext.delete(followed)
            }
        }
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

struct BugListView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\FollowedComponent.position),
                  SortDescriptor(\FollowedComponent.addedAt)])
    private var followedComponents: [FollowedComponent]

    let selection: SidebarSelection?
    @Binding var selectedBugID: Bug.ID?

    @State private var bugs: [Bug] = []
    @State private var totalMatches: Int?
    @State private var isLoading = false
    @State private var loadError: String?

    private static let pageLimit = 50

    var body: some View {
        Group {
            if selection == nil {
                ContentUnavailableView(
                    "Pick something",
                    systemImage: "sidebar.left",
                    description: Text("Choose a smart list or component on the left.")
                )
            } else if isLoading && bugs.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load bugs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if bugs.isEmpty {
                ContentUnavailableView(
                    "No bugs",
                    systemImage: "tray",
                    description: Text("Nothing matches this filter.")
                )
            } else {
                List(selection: $selectedBugID) {
                    ForEach(sortedBugs) { bug in
                        BugRow(bug: bug)
                            .tag(Optional(bug.id))
                            .draggable(BugTransfer(id: bug.id, summary: bug.summary)) {
                                Label("#\(bug.id) \(bug.summary)", systemImage: "ant")
                                    .padding(8)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .contextMenu {
                                addAsMetaMenu(for: bug)
                            }
                    }
                    if let total = totalMatches, total > bugs.count {
                        Text("Showing \(bugs.count) of \(total). Refine the search to narrow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                sortMenu
            }
        }
        .task(id: loadKey) { await load() }
    }

    private var sortMenu: some View {
        @Bindable var workspace = workspace
        return Menu {
            Picker(selection: $workspace.bugListSort) {
                ForEach(BugListSort.allCases) { option in
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

    private var sortedBugs: [Bug] {
        switch workspace.bugListSort {
        case .newest:
            return bugs.sorted {
                ($0.creationTime ?? .distantPast) > ($1.creationTime ?? .distantPast)
            }
        case .recent:
            return bugs.sorted {
                ($0.lastChangeTime ?? .distantPast) > ($1.lastChangeTime ?? .distantPast)
            }
        case .oldest:
            return bugs.sorted {
                ($0.creationTime ?? .distantFuture) < ($1.creationTime ?? .distantFuture)
            }
        case .priority:
            return bugs.sorted {
                priorityRank($0.priority) < priorityRank($1.priority)
            }
        }
    }

    private func priorityRank(_ priority: String?) -> Int {
        switch priority?.uppercased() {
        case "P1": return 1
        case "P2": return 2
        case "P3": return 3
        case "P4": return 4
        case "P5": return 5
        default: return Int.max
        }
    }

    @ViewBuilder
    private func addAsMetaMenu(for bug: Bug) -> some View {
        if followedComponents.isEmpty {
            Button("Add as Meta Bug…") {}
                .disabled(true)
        } else {
            Menu("Add as Meta Bug") {
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
        BugListLoadKey(selection: selection, search: workspace.searchText)
    }

    private var title: String {
        guard let selection else { return "Zilla" }
        switch selection {
        case .smart(let s): return s.title
        case .component(let ref): return "\(ref.product) :: \(ref.component)"
        case .metaBug(let id): return "Meta \(id)"
        }
    }

    private func load() async {
        guard let selection else {
            bugs = []
            totalMatches = nil
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }

        var query = workspace.bugQuery(for: selection)
        if let login = auth.currentUser?.name {
            query = query.substitutingMe(with: login)
        }
        let trimmed = workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.quicksearch = trimmed
        }
        query.limit = Self.pageLimit
        query.includeFields = [
            "id", "summary", "status", "resolution", "product", "component",
            "assigned_to", "priority", "severity", "keywords",
            "last_change_time", "creation_time"
        ]

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let result = try await auth.client.searchBugs(query)
            bugs = result.bugs
            totalMatches = result.totalMatches
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            bugs = []
            totalMatches = nil
        }
    }
}

private struct BugListLoadKey: Hashable {
    let selection: SidebarSelection?
    let search: String
}

private struct BugRow: View {
    let bug: Bug

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .imageScale(.large)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(bug.summary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(verbatim: "#\(bug.id)")
                    Text(verbatim: "·")
                    Text(bug.status)
                    if let assignee = friendlyAssignee {
                        Text(verbatim: "·")
                        Text(assignee)
                            .lineLimit(1)
                    }
                    if let when = bug.lastChangeTime {
                        Text(verbatim: "·")
                        Text(when, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        switch bug.status.uppercased() {
        case "RESOLVED", "VERIFIED", "CLOSED": return "checkmark.circle.fill"
        case "ASSIGNED", "IN_PROGRESS": return "circle.lefthalf.filled"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch bug.status.uppercased() {
        case "RESOLVED", "VERIFIED", "CLOSED": return .green
        case "ASSIGNED", "IN_PROGRESS": return .blue
        default: return .secondary
        }
    }

    private var friendlyAssignee: String? {
        guard let raw = bug.assignedTo, !raw.isEmpty else { return nil }
        if raw.contains("nobody") { return nil }
        if let at = raw.firstIndex(of: "@") {
            return String(raw[..<at])
        }
        return raw
    }
}

#Preview {
    ContentView()
        .environment(Workspace.preview)
        .environment(AuthStore())
}
