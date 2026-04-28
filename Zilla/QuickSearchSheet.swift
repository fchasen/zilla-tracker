//
//  QuickSearchSheet.swift
//  Zilla
//

import SwiftUI
import BugzillaKit

struct QuickSearchSheet: View {
    let onPickBug: (Bug.ID) -> Void
    var onPickUser: ((User) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    @State private var query: String = ""
    @State private var committedQuery: String = ""
    @State private var bugResults: [Bug] = []
    @State private var userResults: [User] = []
    @State private var pinnedUser: User?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedRowID: String?

    @FocusState private var focused: Field?

    private enum Field: Hashable { case search, list }

    private enum Mode: Equatable {
        case empty
        case bug(Bug.ID)
        case freetext(String)
        case users(String)
        case userBugs(User)
    }

    private var mode: Mode {
        if let user = pinnedUser { return .userBugs(user) }
        let trimmed = committedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if trimmed.hasPrefix("#") {
            let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if let id = Int(rest), id > 0 { return .bug(id) }
            return .empty
        }
        if trimmed.hasPrefix("@") {
            let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? .empty : .users(rest)
        }
        return .freetext(trimmed)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Quick Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 620)
        #endif
        .task(id: searchKey) { await runSearch() }
        .onAppear { focused = .search }
        .onChange(of: bugResults) { _, _ in syncSelection() }
        .onChange(of: userResults) { _, _ in syncSelection() }
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            if let user = pinnedUser {
                userChip(user)
            }

            TextField(placeholderText, text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .submitLabel(.search)
                .focused($focused, equals: .search)
                .onSubmit { commitQuery() }
                .onKeyPress(.tab) { focusList() ? .handled : .ignored }
                .onKeyPress(.delete) {
                    if pinnedUser != nil && query.isEmpty {
                        pinnedUser = nil
                        committedQuery = ""
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func userChip(_ user: User) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .imageScale(.small)
            Text(user.displayHandle)
                .lineLimit(1)
            Button {
                pinnedUser = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove user filter")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.tint.opacity(0.18), in: Capsule())
        .foregroundStyle(.tint)
    }

    private var placeholderText: String {
        if pinnedUser != nil {
            return "Filter this user's bugs (↩ to search)"
        }
        return "#bug · @user · text — ↩ to search"
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .empty:
            hint
        case .users:
            if isLoading && userResults.isEmpty {
                loadingView
            } else if let loadError {
                errorView(loadError)
            } else if userResults.isEmpty {
                ContentUnavailableView(
                    "No users",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Nothing matched that name.")
                )
            } else {
                userList
            }
        case .bug, .freetext, .userBugs:
            if isLoading && bugResults.isEmpty {
                loadingView
            } else if let loadError {
                errorView(loadError)
            } else if bugResults.isEmpty {
                ContentUnavailableView(
                    "No bugs",
                    systemImage: "tray",
                    description: Text("Nothing matches.")
                )
            } else {
                bugList
            }
        }
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 14) {
            hintRow(
                symbol: "number",
                title: "#1234",
                description: "Open a bug by its number."
            )
            hintRow(
                symbol: "at",
                title: "@user",
                description: "Find a Bugzilla user, then drill into their bugs."
            )
            hintRow(
                symbol: "text.magnifyingglass",
                title: "search text",
                description: "Free-text quicksearch across summaries."
            )
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func hintRow(symbol: String, title: String, description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.monospaced())
                Text(description).foregroundStyle(.secondary)
            }
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView(
            "Search failed",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }

    private var bugList: some View {
        List(bugResults, id: \.id, selection: $selectedRowID) { bug in
            QuickSearchBugRow(bug: bug)
                .tag("bug:\(bug.id)")
                .contentShape(Rectangle())
                .onTapGesture {
                    onPickBug(bug.id)
                    dismiss()
                }
        }
        .focused($focused, equals: .list)
        .onKeyPress(.return) { commitSelection() ? .handled : .ignored }
        .onKeyPress(keys: [.tab]) { press in
            if press.modifiers.contains(.shift) {
                focused = .search
                return .handled
            }
            return .ignored
        }
    }

    private var userList: some View {
        List(userResults, id: \.id, selection: $selectedRowID) { user in
            QuickSearchUserRow(user: user)
                .tag("user:\(user.id)")
                .contentShape(Rectangle())
                .onTapGesture { pickUser(user) }
        }
        .focused($focused, equals: .list)
        .onKeyPress(.return) { commitSelection() ? .handled : .ignored }
        .onKeyPress(keys: [.tab]) { press in
            if press.modifiers.contains(.shift) {
                focused = .search
                return .handled
            }
            return .ignored
        }
    }

    private struct SearchKey: Hashable {
        let mode: String
        let bugID: Int?
        let text: String
        let userName: String?
    }

    private var searchKey: SearchKey {
        switch mode {
        case .empty: return SearchKey(mode: "empty", bugID: nil, text: "", userName: nil)
        case .bug(let id): return SearchKey(mode: "bug", bugID: id, text: "", userName: nil)
        case .freetext(let text): return SearchKey(mode: "freetext", bugID: nil, text: text, userName: nil)
        case .users(let text): return SearchKey(mode: "users", bugID: nil, text: text, userName: nil)
        case .userBugs(let user): return SearchKey(mode: "userBugs", bugID: nil, text: committedQuery, userName: user.name)
        }
    }

    private func commitQuery() {
        committedQuery = query
    }

    private func runSearch() async {
        loadError = nil
        switch mode {
        case .empty:
            bugResults = []
            userResults = []
            isLoading = false
        case .bug(let id):
            await loadBug(id: id)
        case .freetext(let text):
            await loadFreetext(text)
        case .users(let prefix):
            await loadUsers(matching: prefix)
        case .userBugs:
            await loadUserBugs()
        }
    }

    private func loadBug(id: Bug.ID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let bug = try await auth.client.getBug(id: id)
            bugResults = [bug]
            userResults = []
        } catch BugzillaError.notFound {
            bugResults = []
            userResults = []
        } catch is CancellationError {
        } catch {
            bugResults = []
            userResults = []
            loadError = error.localizedDescription
        }
    }

    private func loadFreetext(_ text: String) async {
        isLoading = true
        defer { isLoading = false }
        var query = BugQuery(quicksearch: text)
        query.limit = 30
        query.order = "changeddate DESC"
        query.includeFields = Self.bugIncludeFields
        do {
            let result = try await auth.client.searchBugs(query)
            bugResults = result.bugs
            userResults = []
        } catch is CancellationError {
        } catch {
            bugResults = []
            userResults = []
            loadError = error.localizedDescription
        }
    }

    private func loadUsers(matching prefix: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let users = try await auth.client.searchUsers(match: prefix, limit: 25)
            userResults = users
            bugResults = []
        } catch is CancellationError {
        } catch {
            userResults = []
            bugResults = []
            loadError = error.localizedDescription
        }
    }

    private func loadUserBugs() async {
        guard let user = pinnedUser else { return }
        isLoading = true
        defer { isLoading = false }
        var query = BugQuery(
            resolution: ["---"],
            userInvolved: user.name
        )
        query.limit = 30
        query.order = "changeddate DESC"
        query.includeFields = Self.bugIncludeFields
        let trimmed = committedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            query.quicksearch = trimmed
        }
        do {
            let result = try await auth.client.searchBugs(query)
            bugResults = result.bugs
            userResults = []
        } catch is CancellationError {
        } catch {
            bugResults = []
            userResults = []
            loadError = error.localizedDescription
        }
    }

    private func pickUser(_ user: User) {
        if let onPickUser {
            onPickUser(user)
            dismiss()
            return
        }
        pinnedUser = user
        query = ""
        committedQuery = ""
        userResults = []
        bugResults = []
        focused = .search
    }

    @discardableResult
    private func focusList() -> Bool {
        if !bugResults.isEmpty {
            if selectedRowID == nil { selectedRowID = "bug:\(bugResults[0].id)" }
            focused = .list
            return true
        }
        if !userResults.isEmpty {
            if selectedRowID == nil { selectedRowID = "user:\(userResults[0].id)" }
            focused = .list
            return true
        }
        return false
    }

    @discardableResult
    private func commitSelection() -> Bool {
        let id = selectedRowID
            ?? bugResults.first.map { "bug:\($0.id)" }
            ?? userResults.first.map { "user:\($0.id)" }
        guard let id else { return false }
        if id.hasPrefix("bug:"), let bugID = Int(id.dropFirst(4)) {
            onPickBug(bugID)
            dismiss()
            return true
        }
        if id.hasPrefix("user:"), let userID = Int(id.dropFirst(5)),
           let user = userResults.first(where: { $0.id == userID }) {
            pickUser(user)
            return true
        }
        return false
    }

    private func syncSelection() {
        let valid: Set<String> = Set(
            bugResults.map { "bug:\($0.id)" } + userResults.map { "user:\($0.id)" }
        )
        if let current = selectedRowID, valid.contains(current) { return }
        selectedRowID = valid.sorted().first(where: { $0.hasPrefix("bug:") })
            ?? valid.sorted().first(where: { $0.hasPrefix("user:") })
    }

    private static let bugIncludeFields = [
        "id", "summary", "status", "resolution", "product", "component",
        "assigned_to", "priority", "severity", "type", "last_change_time"
    ]
}

private struct QuickSearchBugRow: View {
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
                    BugTypePill(type: bug.type)
                    Text(verbatim: "\(bug.id)")
                    Text(verbatim: "·")
                    Text(bug.status.bugzillaTitleCased)
                    Text(verbatim: "·")
                    Text("\(bug.product) :: \(bug.component)")
                        .lineLimit(1)
                        .truncationMode(.middle)
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

    private var statusIcon: String {
        if isClosed { return "checkmark.circle.fill" }
        return "circle"
    }

    private var statusColor: Color {
        if isClosed { return .green }
        switch bug.status.uppercased() {
        case "ASSIGNED", "IN_PROGRESS": return .blue
        default: return .secondary
        }
    }
}

private struct QuickSearchUserRow: View {
    let user: User

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
                .imageScale(.large)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.realName ?? user.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let nick = user.nick, !nick.isEmpty {
                        Text(":\(nick)")
                    }
                    Text(user.name)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

extension User {
    var displayHandle: String {
        if let nick, !nick.isEmpty { return ":\(nick)" }
        if let realName, !realName.isEmpty { return realName }
        return name
    }
}
