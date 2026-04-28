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

// MARK: - Pills

struct BugTypePill: View {
    let type: String?
    var linkTransfer: BugLinkTransfer? = nil

    var body: some View {
        if let info {
            if let transfer = linkTransfer {
                icon(info)
                    .draggable(transfer) {
                        Label("#\(transfer.id) \(transfer.summary)", systemImage: "ant")
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            } else {
                icon(info)
            }
        }
    }

    private func icon(_ info: (symbol: String, color: Color, label: String)) -> some View {
        Image(systemName: info.symbol)
            .foregroundStyle(info.color)
            .help(info.label)
            .accessibilityLabel(info.label)
    }

    private var info: (symbol: String, color: Color, label: String)? {
        switch type?.lowercased() {
        case "defect": return ("ant.fill", .red, "Defect")
        case "enhancement": return ("sparkles", .indigo, "Enhancement")
        case "task": return ("clipboard", .gray, "Task")
        default:
            return linkTransfer == nil ? nil : ("ant.fill", .secondary, "Bug")
        }
    }
}

// MARK: - Drag payload

struct BugTransfer: Codable, Transferable {
    let id: Int
    let summary: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

struct BugLinkTransfer: Codable, Transferable {
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

enum ReviewList: String, CaseIterable, Hashable, Identifiable {
    case review
    case active
    case landed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .review: return "Review"
        case .landed: return "Landed"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "doc.text"
        case .review: return "checkmark.seal"
        case .landed: return "shippingbox"
        }
    }
}

enum SidebarSelection: Hashable {
    case smart(SmartEndpoint)
    case allDrafts
    case review(ReviewList)
    case component(ComponentRef)
    case metaBug(Int)
}

enum BugListSort: String, CaseIterable, Identifiable, Hashable {
    case ordered, newest, recent, oldest, priority

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ordered: return "Ordered"
        case .newest: return "Newest"
        case .recent: return "Recent"
        case .oldest: return "Oldest"
        case .priority: return "Priority"
        }
    }

    var systemImage: String {
        switch self {
        case .ordered: return "list.number"
        case .newest: return "arrow.down.circle"
        case .recent: return "clock"
        case .oldest: return "arrow.up.circle"
        case .priority: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Workspace

struct DependencyMetadata: Sendable, Hashable {
    let id: Bug.ID
    let summary: String
    let status: String
    let resolution: String

    var isClosed: Bool {
        ["RESOLVED", "VERIFIED", "CLOSED"].contains(status.uppercased())
    }
}

@Observable
final class Workspace {
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?

    var sidebarSelection: SidebarSelection? = .smart(.myBugs) {
        didSet {
            if oldValue != sidebarSelection { activeRevisionID = nil }
        }
    }
    var selectedBugID: Bug.ID? {
        didSet {
            if oldValue != selectedBugID { activeRevisionID = nil }
        }
    }
    var selectedDraftID: UUID?
    var activeRevisionID: Int?
    var phabricatorSettingsPresented: Bool = false
    var searchText: String = ""
    var smartSorts: [SmartEndpoint: BugListSort] = [:]
    var componentSort: BugListSort = .priority
    var bugListRefreshToken: UUID = UUID()

    var bugListSort: BugListSort {
        get {
            if case let .smart(endpoint) = sidebarSelection {
                return smartSorts[endpoint] ?? Self.defaultSort(for: endpoint)
            }
            return componentSort
        }
        set {
            if case let .smart(endpoint) = sidebarSelection {
                smartSorts[endpoint] = newValue
            } else {
                componentSort = newValue
            }
        }
    }

    private static func defaultSort(for endpoint: SmartEndpoint) -> BugListSort {
        switch endpoint {
        case .myBugs: return .ordered
        default: return .recent
        }
    }

    // Active bug (loaded once per selection; shared with the inspector).
    private(set) var loadedBug: Bug?
    private(set) var loadedComments: [Comment] = []
    private(set) var isLoadingBug = false
    private(set) var bugLoadError: String?

    // Bug list loading flag, used by the (now centralized) refresh button.
    var isLoadingBugList: Bool = false

    // Bug-update flag, drives the toolbar progress indicator.
    private(set) var isUpdatingBug = false

    var lastLinkError: String?

    var showInspector: Bool = false

    private(set) var dependencyMetadata: [Bug.ID: DependencyMetadata] = [:]

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
        selectedDraftID = nil
        activeRevisionID = nil
        searchText = ""
        clearLoadedBug()
        showInspector = false
        dependencyMetadata = [:]
    }

    @MainActor
    func loadBug(id: Bug.ID, using client: BugzillaClient) async {
        isLoadingBug = true
        bugLoadError = nil
        defer { isLoadingBug = false }
        do {
            async let bugTask = client.getBug(id: id)
            async let commentsTask = client.comments(bugID: id)
            loadedBug = try await bugTask
            loadedComments = try await commentsTask
        } catch is CancellationError {
            return
        } catch {
            loadedBug = nil
            loadedComments = []
            bugLoadError = error.localizedDescription
        }
    }

    @MainActor
    func clearLoadedBug() {
        loadedBug = nil
        loadedComments = []
        bugLoadError = nil
    }

    @discardableResult
    @MainActor
    func applyBugUpdate(_ update: BugUpdate, using client: BugzillaClient) async -> Error? {
        guard let id = loadedBug?.id else { return nil }
        isUpdatingBug = true
        defer { isUpdatingBug = false }
        do {
            _ = try await client.updateBug(id: id, update)
            if let refreshed = try? await client.getBug(id: id) {
                loadedBug = refreshed
            }
            if let refreshed = try? await client.comments(bugID: id) {
                loadedComments = refreshed
            }
            return nil
        } catch {
            return error
        }
    }

    @discardableResult
    @MainActor
    func linkBlocking(source: Bug.ID, target: Bug.ID, using client: BugzillaClient) async -> Error? {
        guard source != target else { return nil }
        if loadedBug?.id == source, loadedBug?.blocks.contains(target) == true {
            return nil
        }
        if loadedBug?.id == target, loadedBug?.dependsOn.contains(source) == true {
            return nil
        }
        isUpdatingBug = true
        defer { isUpdatingBug = false }
        do {
            _ = try await client.updateBug(
                id: source,
                BugUpdate(blocks: BugRelationUpdate(add: [target]))
            )
            if let id = loadedBug?.id, id == source || id == target {
                if let refreshed = try? await client.getBug(id: id) {
                    loadedBug = refreshed
                }
            }
            await loadDependencyMetadata(ids: [source, target], using: client)
            return nil
        } catch {
            return error
        }
    }

    @MainActor
    func refreshLoadedComments(using client: BugzillaClient) async {
        guard let id = loadedBug?.id else { return }
        if let refreshed = try? await client.comments(bugID: id) {
            loadedComments = refreshed
        }
    }

    @MainActor
    func loadDependencyMetadata(ids: [Bug.ID], using client: BugzillaClient) async {
        let needed = ids.filter { dependencyMetadata[$0] == nil }
        guard !needed.isEmpty else { return }
        guard let bugs = try? await client.getBugs(ids: needed) else { return }
        for bug in bugs {
            dependencyMetadata[bug.id] = DependencyMetadata(
                id: bug.id,
                summary: bug.summary,
                status: bug.status,
                resolution: bug.resolution
            )
        }
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
        case .allDrafts, .review:
            return BugQuery()
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
    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.modelContext) private var modelContext
    @Query private var followedMetaBugs: [FollowedMetaBug]

    var body: some View {
        @Bindable var workspace = workspace

        NavigationSplitView {
            Sidebar(selection: $workspace.sidebarSelection)
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    createDraft()
                } label: {
                    Label("New Bug", systemImage: "square.and.pencil")
                }
                .help(newBugHelpText)
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
                    Button("Phabricator…") {
                        workspace.phabricatorSettingsPresented = true
                    }
                    Divider()
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
        .inspector(isPresented: $workspace.showInspector) {
            inspectorColumn
                .inspectorColumnWidth(min: 220, ideal: 280, max: 360)
        }
        .sheet(isPresented: $workspace.phabricatorSettingsPresented) {
            PhabricatorSettingsView()
        }
        .alert(
            "Couldn't link bugs",
            isPresented: Binding(
                get: { workspace.lastLinkError != nil },
                set: { if !$0 { workspace.lastLinkError = nil } }
            ),
            actions: { Button("OK") { workspace.lastLinkError = nil } },
            message: { Text(workspace.lastLinkError ?? "") }
        )
        .task {
            if workspace.products.isEmpty {
                await workspace.loadProducts(using: auth.client)
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        @Bindable var workspace = workspace
        switch workspace.sidebarSelection {
        case .review(let list):
            RevisionListView(list: list)
        default:
            BugListView(selection: workspace.sidebarSelection,
                        selectedBugID: $workspace.selectedBugID)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let id = workspace.activeRevisionID {
            RevisionWebView(revisionID: id) {
                workspace.activeRevisionID = nil
            }
        } else if workspace.sidebarSelection == .allDrafts, let id = workspace.selectedDraftID {
            DraftEditorView(draftID: id)
        } else {
            BugDetailView(bugID: workspace.selectedBugID)
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if workspace.activeRevisionID != nil {
            EmptyView()
        } else if workspace.sidebarSelection == .allDrafts, let id = workspace.selectedDraftID {
            DraftInspector(draftID: id)
        } else {
            BugInspector()
        }
    }

    private var newBugHelpText: String {
        switch workspace.sidebarSelection {
        case .component(let ref):
            return "New bug in \(ref.component)"
        case .metaBug(let id):
            return "New bug blocking #\(id)"
        case .smart, .allDrafts, .review, .none:
            return "New bug…"
        }
    }

    private func createDraft() {
        let draft = BugDraft()
        switch workspace.sidebarSelection {
        case .component(let ref):
            draft.product = ref.product
            draft.componentName = ref.component
        case .metaBug(let bugId):
            if let meta = followedMetaBugs.first(where: { $0.bugId == bugId }),
               let parent = meta.component {
                draft.product = parent.product
                draft.componentName = parent.componentName
            }
            draft.blocks = [bugId]
        case .smart, .allDrafts, .review, .none:
            break
        }
        modelContext.insert(draft)
        workspace.sidebarSelection = .allDrafts
        workspace.selectedDraftID = draft.id
        workspace.showInspector = true
    }
}

private struct BugInspector: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    var body: some View {
        if let bug = workspace.loadedBug {
            ScrollView {
                BugInspectorContent(
                    bug: bug,
                    onUpdate: { update in
                        Task { await workspace.applyBugUpdate(update, using: auth.client) }
                    },
                    onOpenBug: { id in
                        workspace.selectedBugID = id
                    }
                )
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "No bug selected",
                systemImage: "sidebar.right",
                description: Text("Select a bug to see its details.")
            )
        }
    }
}

private struct DraftInspector: View {
    let draftID: UUID

    @Query private var matchingDrafts: [BugDraft]

    init(draftID: UUID) {
        self.draftID = draftID
        self._matchingDrafts = Query(filter: #Predicate<BugDraft> { $0.id == draftID })
    }

    var body: some View {
        if let draft = matchingDrafts.first {
            ScrollView {
                DraftMetadata(draft: draft)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView(
                "No draft",
                systemImage: "sidebar.right",
                description: Text("Pick a draft on the left.")
            )
        }
    }
}

private struct DraftMetadata: View {
    @Bindable var draft: BugDraft

    @State private var showComponentPicker = false

    private static let typeOptions: [(code: String?, label: String)] = [
        (nil, "—"),
        ("defect", "Defect"),
        ("enhancement", "Enhancement"),
        ("task", "Task")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            componentSection
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                typeRow
                menuRow(
                    label: "Priority",
                    current: draft.priority,
                    options: BugMetadata.priorityOptions
                ) { value in
                    draft.priority = (value == "--") ? nil : value
                    draft.updatedAt = .now
                }
                menuRow(
                    label: "Severity",
                    current: draft.severity,
                    options: BugMetadata.severityOptions
                ) { value in
                    draft.severity = (value == "--") ? nil : value
                    draft.updatedAt = .now
                }
                assigneeRow
                keywordsRow
                whiteboardRow
                blocksRow
                datesRow
            }
        }
        .font(.callout)
        .sheet(isPresented: $showComponentPicker) {
            ComponentPickerSheet(onPick: { product, component in
                draft.product = product.name
                draft.componentName = component.name
                draft.updatedAt = .now
            })
        }
    }

    @ViewBuilder
    private var componentSection: some View {
        let isMetaSeeded = !draft.blocks.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Text("Component").foregroundStyle(.secondary).font(.caption)
            if let ref = draft.componentRef {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ref.component)
                        Text(ref.product)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !isMetaSeeded {
                        Button("Change…") { showComponentPicker = true }
                            .buttonStyle(.borderless)
                    }
                }
            } else {
                Button {
                    showComponentPicker = true
                } label: {
                    Label("Pick component…", systemImage: "shippingbox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            if isMetaSeeded {
                Text("Inherited from blocked meta bug")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var typeRow: some View {
        GridRow {
            Text("Type").foregroundStyle(.secondary)
            Menu {
                ForEach(Self.typeOptions, id: \.label) { option in
                    Button {
                        draft.type = option.code
                        draft.updatedAt = .now
                    } label: {
                        if option.code == draft.type {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Text(typeLabel)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var typeLabel: String {
        Self.typeOptions.first(where: { $0.code == draft.type })?.label ?? "—"
    }

    @ViewBuilder
    private func menuRow(
        label: String,
        current: String?,
        options: [String],
        onPick: @escaping (String) -> Void
    ) -> some View {
        let displayed = (current?.isEmpty == false ? current : nil) ?? "--"
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Menu {
                ForEach(options, id: \.self) { value in
                    Button {
                        onPick(value)
                    } label: {
                        if value == current || (value == "--" && (current == nil || current?.isEmpty == true)) {
                            Label(value, systemImage: "checkmark")
                        } else {
                            Text(value)
                        }
                    }
                }
            } label: {
                Text(displayed)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var assigneeRow: some View {
        GridRow {
            Text("Assignee").foregroundStyle(.secondary)
            TextField("default assignee", text: Binding(
                get: { draft.assignedTo ?? "" },
                set: { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.assignedTo = trimmed.isEmpty ? nil : newValue
                    draft.updatedAt = .now
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var keywordsRow: some View {
        GridRow {
            Text("Keywords").foregroundStyle(.secondary)
            TextField("comma-separated", text: $draft.keywordsCSV)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft.keywordsCSV) { draft.updatedAt = .now }
        }
    }

    @ViewBuilder
    private var whiteboardRow: some View {
        GridRow {
            Text("Whiteboard").foregroundStyle(.secondary)
            TextField("[tag1][tag2]…", text: $draft.whiteboard)
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft.whiteboard) { draft.updatedAt = .now }
        }
    }

    @ViewBuilder
    private var blocksRow: some View {
        if !draft.blocks.isEmpty {
            GridRow {
                Text("Blocks").foregroundStyle(.secondary)
                Text(draft.blocks.map { "#\($0)" }.joined(separator: ", "))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var datesRow: some View {
        GridRow {
            Text("Updated").foregroundStyle(.secondary)
            Text(draft.updatedAt, format: .relative(presentation: .named))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\FollowedComponent.position),
                  SortDescriptor(\FollowedComponent.addedAt)])
    private var followedComponents: [FollowedComponent]
    @Query(sort: [SortDescriptor(\BugDraft.updatedAt, order: .reverse)])
    private var drafts: [BugDraft]

    @Binding var selection: SidebarSelection?

    @State private var addMetaBugTarget: FollowedComponent?
    @State private var showAddComponent = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(SmartEndpoint.allCases) { endpoint in
                        Label(endpoint.title, systemImage: endpoint.systemImage)
                            .tag(SidebarSelection.smart(endpoint))
                    }
                    Label {
                        HStack {
                            Text("Drafts")
                            Spacer()
                            if !drafts.isEmpty {
                                Text("\(drafts.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tag(SidebarSelection.allDrafts)
                }

                Section("Review") {
                    ForEach(ReviewList.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(SidebarSelection.review(item))
                    }
                }

                Section("Components") {
                    if followedComponents.isEmpty {
                        Text("No components yet. Tap + below to follow one.")
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

            Divider()
            HStack {
                Button {
                    showAddComponent = true
                } label: {
                    Label("Add Component", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .help("Add Component")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle("Zilla")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        #endif
        .sheet(item: $addMetaBugTarget) { component in
            MetaBugPickerSheet(component: component)
        }
        .sheet(isPresented: $showAddComponent) {
            ComponentPickerSheet()
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

private struct DraftRow: View {
    let draft: BugDraft

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.displaySummary).lineLimit(1)
                Text(draft.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.and.pencil")
        }
    }
}

private struct AllDraftsList: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\BugDraft.updatedAt, order: .reverse)])
    private var drafts: [BugDraft]

    var body: some View {
        @Bindable var workspace = workspace

        Group {
            if drafts.isEmpty {
                ContentUnavailableView(
                    "No drafts",
                    systemImage: "square.and.pencil",
                    description: Text("Tap + to start a new bug.")
                )
            } else {
                List(selection: $workspace.selectedDraftID) {
                    ForEach(drafts) { draft in
                        DraftListRow(draft: draft)
                            .tag(Optional(draft.id))
                            .contextMenu {
                                Button("Discard", role: .destructive) {
                                    if workspace.selectedDraftID == draft.id {
                                        workspace.selectedDraftID = nil
                                    }
                                    modelContext.delete(draft)
                                }
                            }
                    }
                }
            }
        }
    }
}

private struct DraftListRow: View {
    let draft: BugDraft

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.secondary)
                .imageScale(.large)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(draft.displaySummary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(draft.displaySubtitle)
                    if let firstBlocks = draft.blocks.first {
                        Text(verbatim: "·")
                        Text("blocks #\(firstBlocks)")
                    }
                    Text(verbatim: "·")
                    Text(draft.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
                    .contextMenu { componentMenu }
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
                        .contextMenu { componentMenu }
                }
            }
        }
        .background(
            isDropTarget
                ? Color.accentColor.opacity(0.18)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
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

    @ViewBuilder
    private var componentMenu: some View {
        Button("Add Meta Bug…") { onAddMetaBug() }
        Divider()
        Button("Remove", role: .destructive) {
            modelContext.delete(followed)
        }
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
    @Query private var orderEntries: [BugOrderEntry]

    let selection: SidebarSelection?
    @Binding var selectedBugID: Bug.ID?

    @State private var bugs: [Bug] = []
    @State private var totalMatches: Int?
    @State private var isLoading = false
    @State private var loadError: String?

    private static let pageLimit = 50

    private var isAllDrafts: Bool {
        selection == .allDrafts
    }

    private var endpointKey: String? {
        if case let .smart(endpoint) = selection {
            return "smart.\(endpoint.rawValue)"
        }
        return nil
    }

    private var supportsOrdered: Bool {
        endpointKey != nil
    }

    private var isOrdered: Bool {
        supportsOrdered && workspace.bugListSort == .ordered
    }

    var body: some View {
        Group {
            if selection == nil {
                ContentUnavailableView(
                    "Pick something",
                    systemImage: "sidebar.left",
                    description: Text("Choose a smart list or component on the left.")
                )
            } else if isAllDrafts {
                AllDraftsList()
            } else if isLoading && bugs.isEmpty {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView(
                    "Couldn't load bugs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .textSelection(.enabled)
            } else if bugs.isEmpty {
                ContentUnavailableView(
                    "No bugs",
                    systemImage: "tray",
                    description: Text("Nothing matches this filter.")
                )
            } else {
                List(selection: $selectedBugID) {
                    let sorted = sortedBugs
                    ReorderZone(
                        endpointKey: endpointKey,
                        zoneIndex: 0,
                        displayed: sorted,
                        entries: orderEntries,
                        isEnabled: isOrdered
                    )
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, bug in
                        row(for: bug)
                        ReorderZone(
                            endpointKey: endpointKey,
                            zoneIndex: index + 1,
                            displayed: sorted,
                            entries: orderEntries,
                            isEnabled: isOrdered
                        )
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
            if !isAllDrafts {
                ToolbarItem(placement: .primaryAction) {
                    refreshButton
                }
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
        }
        .searchable(
            text: searchBinding,
            prompt: "Search bugs"
        )
        .task(id: loadKey) { await load() }
        .onChange(of: selection) { _, _ in
            bugs = []
            totalMatches = nil
            loadError = nil
        }
    }

    @ViewBuilder
    private func row(for bug: Bug) -> some View {
        BugRow(bug: bug)
            .tag(Optional(bug.id))
            .draggable(BugTransfer(id: bug.id, summary: bug.summary)) {
                Label("#\(bug.id) \(bug.summary)", systemImage: "ant")
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .bugLinkDrop(target: bug.id)
            .contextMenu {
                addAsMetaMenu(for: bug)
            }
    }

    private var searchBinding: Binding<String> {
        @Bindable var workspace = workspace
        return $workspace.searchText
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
        .keyboardShortcut("r", modifiers: .command)
    }

    private var sortMenu: some View {
        @Bindable var workspace = workspace
        return Menu {
            Picker(selection: $workspace.bugListSort) {
                ForEach(availableSorts) { option in
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

    private var availableSorts: [BugListSort] {
        BugListSort.allCases.filter { $0 != .ordered || supportsOrdered }
    }

    private var sortedBugs: [Bug] {
        switch workspace.bugListSort {
        case .ordered:
            return orderedBugs
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
            return bugs.sorted { lhs, rhs in
                let lhsClosed = isClosed(lhs)
                let rhsClosed = isClosed(rhs)
                if lhsClosed != rhsClosed { return !lhsClosed }
                return priorityRank(lhs.priority) < priorityRank(rhs.priority)
            }
        }
    }

    private var orderedBugs: [Bug] {
        guard let key = endpointKey else {
            return bugs.sorted {
                ($0.lastChangeTime ?? .distantPast) > ($1.lastChangeTime ?? .distantPast)
            }
        }
        var positions: [Bug.ID: Int] = [:]
        for entry in orderEntries where entry.endpointKey == key {
            positions[entry.bugId] = entry.position
        }
        let unpositioned = bugs
            .filter { positions[$0.id] == nil }
            .sorted {
                ($0.lastChangeTime ?? .distantPast) > ($1.lastChangeTime ?? .distantPast)
            }
        let positioned = bugs
            .filter { positions[$0.id] != nil }
            .sorted { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) }
        return unpositioned + positioned
    }

    private func isClosed(_ bug: Bug) -> Bool {
        ["RESOLVED", "VERIFIED", "CLOSED"].contains(bug.status.uppercased())
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
            Button("Add To…") {}
                .disabled(true)
        } else {
            Menu("Add To") {
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
        BugListLoadKey(
            selection: selection,
            search: workspace.searchText,
            refresh: workspace.bugListRefreshToken
        )
    }

    private var title: String {
        guard let selection else { return "Zilla" }
        switch selection {
        case .smart(let s): return s.title
        case .component(let ref): return "\(ref.product) :: \(ref.component)"
        case .metaBug(let id): return "Meta \(id)"
        case .allDrafts: return "Drafts"
        case .review(let r): return r.title
        }
    }

    private func load() async {
        guard let selection else {
            bugs = []
            totalMatches = nil
            return
        }
        if selection == .allDrafts {
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
            "assigned_to", "priority", "severity", "keywords", "type",
            "last_change_time", "creation_time",
            "attachments.id", "attachments.content_type", "attachments.is_obsolete"
        ]

        isLoading = true
        workspace.isLoadingBugList = true
        loadError = nil
        defer {
            isLoading = false
            workspace.isLoadingBugList = false
        }

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
    let refresh: UUID
}

private struct ReorderZone: View {
    @Environment(\.modelContext) private var modelContext

    let endpointKey: String?
    let zoneIndex: Int
    let displayed: [Bug]
    let entries: [BugOrderEntry]
    let isEnabled: Bool

    @State private var isTargeted = false

    var body: some View {
        if isEnabled, let key = endpointKey {
            zoneBase
                .dropDestination(for: BugTransfer.self) { transfers, _ in
                    guard let transfer = transfers.first else { return false }
                    reorder(bugID: transfer.id, key: key)
                    return true
                } isTargeted: { isTargeted = $0 }
        } else {
            zoneBase
        }
    }

    private var zoneBase: some View {
        Color.clear
            .frame(height: 3)
            .overlay(alignment: .center) {
                if isTargeted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 1.5)
                        .padding(.horizontal, 4)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }

    private func reorder(bugID: Bug.ID, key: String) {
        let removeIdx = displayed.firstIndex(where: { $0.id == bugID })
        var newOrder = displayed
        if let idx = removeIdx {
            newOrder.remove(at: idx)
        }
        let insertIdx: Int
        if let removeIdx, removeIdx < zoneIndex {
            insertIdx = max(0, zoneIndex - 1)
        } else {
            insertIdx = min(zoneIndex, newOrder.count)
        }
        guard let bug = displayed.first(where: { $0.id == bugID }) else { return }
        if let removeIdx, removeIdx == insertIdx {
            return
        }
        newOrder.insert(bug, at: insertIdx)

        let preexisting: Set<Bug.ID> = Set(
            entries.filter { $0.endpointKey == key }.map(\.bugId)
        )
        let firstManualIdx = newOrder.firstIndex { $0.id == bugID || preexisting.contains($0.id) }
            ?? newOrder.count

        for i in firstManualIdx..<newOrder.count {
            let candidate = newOrder[i]
            let position = i - firstManualIdx
            if let entry = entries.first(where: {
                $0.endpointKey == key && $0.bugId == candidate.id
            }) {
                if entry.position != position {
                    entry.position = position
                }
            } else {
                modelContext.insert(BugOrderEntry(
                    endpointKey: key,
                    bugId: candidate.id,
                    position: position
                ))
            }
        }
        try? modelContext.save()
    }
}

private struct BugRow: View {
    @Environment(ViewedBugsStore.self) private var viewedBugs
    let bug: Bug

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .imageScale(.large)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if isUnseenAndRecent {
                        Circle()
                            .fill(.blue)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("New")
                    }
                    Text(bug.summary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                ViewThatFits(in: .horizontal) {
                    metadataLine(level: 0)
                    metadataLine(level: 1)
                    metadataLine(level: 2)
                    metadataLine(level: 3)
                    metadataLine(level: 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var isClosed: Bool {
        ["RESOLVED", "VERIFIED", "CLOSED"].contains(bug.status.uppercased())
    }

    private var isUnseenAndRecent: Bool {
        guard !isClosed,
              !viewedBugs.contains(bug.id),
              let created = bug.creationTime else { return false }
        return Date().timeIntervalSince(created) < 7 * 24 * 60 * 60
    }

    private var statusIcon: String {
        if isClosed { return "checkmark.circle.fill" }
        if bug.hasPhabricatorPatch { return "circle.lefthalf.filled" }
        switch bug.status.uppercased() {
        case "ASSIGNED": return "circle"
        case "IN_PROGRESS": return "circle.lefthalf.filled"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        if isClosed { return .green }
        if bug.hasPhabricatorPatch { return .blue }
        switch bug.status.uppercased() {
        case "ASSIGNED", "IN_PROGRESS": return .blue
        default: return .secondary
        }
    }

    private var displayPriority: String? {
        guard let p = bug.priority, !p.isEmpty, p != "--" else { return nil }
        return p
    }

    private var displaySeverity: String? {
        guard let s = bug.severity, !s.isEmpty, s != "--" else { return nil }
        return s
    }

    private func priorityColor(_ value: String?) -> Color {
        switch value?.uppercased() {
        case "P1": return .red
        case "P2": return .orange
        default: return .secondary
        }
    }

    private func severityColor(_ value: String?) -> Color {
        switch value?.uppercased() {
        case "S1", "BLOCKER", "CRITICAL": return .red
        case "S2", "MAJOR": return .orange
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

    @ViewBuilder
    private func metadataLine(level: Int) -> some View {
        HStack(spacing: 6) {
            BugTypePill(type: bug.type)
            Text(verbatim: "\(bug.id)")
            Text(verbatim: "·")
            Text(bug.status.bugzillaTitleCased)
            if level <= 3, let priority = displayPriority {
                Text(verbatim: "·")
                Text(priority)
                    .foregroundStyle(priorityColor(bug.priority))
            }
            if level <= 2, let severity = displaySeverity {
                Text(verbatim: "·")
                Text(severity)
                    .foregroundStyle(severityColor(bug.severity))
            }
            if level <= 1, let assignee = friendlyAssignee {
                Text(verbatim: "·")
                Text(assignee)
            }
            if level <= 0, let when = bug.lastChangeTime {
                Text(verbatim: "·")
                Text(when, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            }
        }
        .lineLimit(1)
    }
}

extension String {
    var bugzillaTitleCased: String {
        replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview {
    ContentView()
        .environment(Workspace.preview)
        .environment(AuthStore())
        .environment(ViewedBugsStore())
}
