//
//  ContentView.swift
//  Zilla
//
//  Created by Fred Chasen on 4/27/26.
//

import SwiftUI
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

// MARK: - Followed entities (placeholder until real product loading)

struct FollowedComponent: Identifiable, Hashable {
    let id = UUID()
    let ref: ComponentRef
    var metaBugs: [FollowedMetaBug]
}

struct FollowedMetaBug: Identifiable, Hashable {
    let id: Int
    let title: String
}

// MARK: - Workspace

@Observable
final class Workspace {
    var followedComponents: [FollowedComponent] = []
    var sidebarSelection: SidebarSelection? = .smart(.myBugs)
    var selectedBugID: Bug.ID?
    var searchText: String = ""

    static var mock: Workspace {
        let ws = Workspace()
        ws.followedComponents = [
            FollowedComponent(
                ref: ComponentRef(product: "Firefox", component: "General"),
                metaBugs: [
                    FollowedMetaBug(id: 1700001, title: "Tab redesign tracking"),
                    FollowedMetaBug(id: 1700042, title: "Sidebar overhaul")
                ]
            ),
            FollowedComponent(
                ref: ComponentRef(product: "Core", component: "DOM: Core & HTML"),
                metaBugs: [
                    FollowedMetaBug(id: 1812345, title: "Custom elements parity")
                ]
            )
        ]
        return ws
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
                        Task { await auth.signOut() }
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(Workspace.self) private var workspace
    @Binding var selection: SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SmartEndpoint.allCases) { endpoint in
                    Label(endpoint.title, systemImage: endpoint.systemImage)
                        .tag(SidebarSelection.smart(endpoint))
                }
            }

            if !workspace.followedComponents.isEmpty {
                Section("Components") {
                    ForEach(workspace.followedComponents) { followed in
                        if followed.metaBugs.isEmpty {
                            ComponentRow(followed: followed)
                                .tag(SidebarSelection.component(followed.ref))
                        } else {
                            DisclosureGroup {
                                ForEach(followed.metaBugs) { meta in
                                    Label {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(meta.title).lineLimit(1)
                                            Text("Bug \(meta.id)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: "circle.dashed")
                                    }
                                    .tag(SidebarSelection.metaBug(meta.id))
                                }
                            } label: {
                                ComponentRow(followed: followed)
                                    .tag(SidebarSelection.component(followed.ref))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Zilla")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        #endif
    }
}

private struct ComponentRow: View {
    let followed: FollowedComponent

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(followed.ref.component).lineLimit(1)
                Text(followed.ref.product)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.stack.3d.up")
        }
    }
}

// MARK: - Bug list (placeholder)

struct BugListView: View {
    @Environment(Workspace.self) private var workspace
    let selection: SidebarSelection?
    @Binding var selectedBugID: Bug.ID?

    var body: some View {
        Group {
            if let selection {
                let query = workspace.bugQuery(for: selection)
                List(selection: $selectedBugID) {
                    Section {
                        Text("No bugs loaded — networking not wired in the UI yet.")
                            .foregroundStyle(.secondary)
                    } header: {
                        QueryHeader(selection: selection, query: query)
                    }
                }
                .navigationTitle(title(for: selection))
            } else {
                ContentUnavailableView(
                    "Pick something",
                    systemImage: "sidebar.left",
                    description: Text("Choose a smart list or component on the left.")
                )
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        #endif
    }

    private func title(for selection: SidebarSelection) -> String {
        switch selection {
        case .smart(let s): return s.title
        case .component(let ref): return "\(ref.product) :: \(ref.component)"
        case .metaBug(let id): return "Meta \(id)"
        }
    }
}

private struct QueryHeader: View {
    let selection: SidebarSelection
    let query: BugQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label(for: selection))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(querySummary(query))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func label(for selection: SidebarSelection) -> String {
        switch selection {
        case .smart(let s): return s.title
        case .component(let ref): return "\(ref.product) :: \(ref.component)"
        case .metaBug(let id): return "Meta bug \(id)"
        }
    }

    private func querySummary(_ q: BugQuery) -> String {
        var parts: [String] = []
        if !q.product.isEmpty { parts.append("product=\(q.product.joined(separator: ","))") }
        if !q.component.isEmpty { parts.append("component=\(q.component.joined(separator: ","))") }
        if !q.assignedTo.isEmpty { parts.append("assigned_to=\(q.assignedTo.joined(separator: ","))") }
        if !q.reporter.isEmpty { parts.append("reporter=\(q.reporter.joined(separator: ","))") }
        if !q.resolution.isEmpty { parts.append("resolution=\(q.resolution.joined(separator: ","))") }
        if !q.blocks.isEmpty { parts.append("blocks=\(q.blocks.map(String.init).joined(separator: ","))") }
        if let r = q.flagRequestee { parts.append("flag_requestee=\(r)") }
        if let n = q.flagName { parts.append("flag_name=\(n)") }
        if let user = q.userInvolved { parts.append("involves=\(user)") }
        if let after = q.changedAfter {
            parts.append("changed_after=\(ISO8601DateFormatter().string(from: after))")
        }
        return parts.isEmpty ? "(no filters)" : parts.joined(separator: " · ")
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
        .environment(Workspace.mock)
        .environment(AuthStore())
}
