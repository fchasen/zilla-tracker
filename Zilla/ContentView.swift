//
//  ContentView.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import SwiftUI
import SwiftData
import BugzillaKit

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

// MARK: - Workspace

@Observable
final class Workspace {
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?

    var sidebarSelection: SidebarSelection? = .smart(.myBugs)
    var selectedBugID: Bug.ID?
    var searchText: String = ""

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
            ToolbarItem(placement: .primaryAction) {
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
            }
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
    @Query(sort: \FollowedComponent.addedAt) private var followedComponents: [FollowedComponent]
    @Binding var selection: SidebarSelection?

    @State private var showAddComponent = false
    @State private var addMetaBugTarget: FollowedComponent?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SmartEndpoint.allCases) { endpoint in
                    Label(endpoint.title, systemImage: endpoint.systemImage)
                        .tag(SidebarSelection.smart(endpoint))
                }
            }

            Section {
                if followedComponents.isEmpty {
                    Text("No components yet. Tap + to follow one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(followedComponents) { followed in
                        FollowedComponentEntry(
                            followed: followed,
                            onAddMetaBug: { addMetaBugTarget = followed },
                            onRemove: { modelContext.delete(followed) },
                            onRemoveMetaBug: { modelContext.delete($0) }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Components")
                    Spacer()
                    Button {
                        showAddComponent = true
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Zilla")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        #endif
        .sheet(isPresented: $showAddComponent) {
            ComponentPickerSheet()
        }
        .sheet(item: $addMetaBugTarget) { component in
            MetaBugPickerSheet(component: component)
        }
    }
}

private struct FollowedComponentEntry: View {
    let followed: FollowedComponent
    let onAddMetaBug: () -> Void
    let onRemove: () -> Void
    let onRemoveMetaBug: (FollowedMetaBug) -> Void

    var body: some View {
        let metas = followed.metaBugs.sorted { $0.addedAt < $1.addedAt }

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
                                    onRemoveMetaBug(meta)
                                }
                            }
                    }
                } label: {
                    FollowedComponentRow(followed: followed)
                        .tag(SidebarSelection.component(followed.ref))
                }
            }
        }
        .contextMenu {
            Button("Add Meta Bug…") { onAddMetaBug() }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
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
                Text(meta.summary).lineLimit(1)
                Text("#\(meta.bugId)")
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
                    ForEach(bugs) { bug in
                        BugRow(bug: bug).tag(Optional(bug.id))
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
        .task(id: loadKey) { await load() }
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
                    Text("#\(bug.id)")
                    Text("·")
                    Text(bug.status)
                    if let assignee = friendlyAssignee {
                        Text("·")
                        Text(assignee)
                            .lineLimit(1)
                    }
                    if let when = bug.lastChangeTime {
                        Text("·")
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

// MARK: - Bug detail (placeholder)

struct BugDetailView: View {
    let bugID: Bug.ID?

    var body: some View {
        if let bugID {
            ContentUnavailableView(
                "Bug \(bugID)",
                systemImage: "ant",
                description: Text("Detail view not implemented yet.")
            )
        } else {
            ContentUnavailableView(
                "No bug selected",
                systemImage: "ant",
                description: Text("Pick a bug from the list to see details.")
            )
        }
    }
}

#Preview {
    ContentView()
        .environment(Workspace.preview)
        .environment(AuthStore())
}
