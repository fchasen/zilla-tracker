import SwiftUI
import PhabricatorKit

struct ProjectPickerSheet: View {
    let excludedPHIDs: Set<String>
    let onPick: (PhabricatorProject) -> Void

    @Environment(PhabricatorAuthStore.self) private var phab
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var results: [PhabricatorProject] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedPHID: String?

    @FocusState private var focused: Field?

    private enum Field: Hashable { case search, list }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search project tags…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.top)
                    .submitLabel(.search)
                    .focused($focused, equals: .search)
                    .onSubmit { focusList() }
                    .onKeyPress(.tab) { focusList() ? .handled : .ignored }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Add tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
        .task(id: query) { await debounce() }
        .task(id: debouncedQuery) { await runSearch() }
        .onAppear { focused = .search }
        .onChange(of: results) { _, new in
            if new.isEmpty {
                selectedPHID = nil
            } else if !new.contains(where: { $0.phid == selectedPHID }) {
                selectedPHID = new.first?.phid
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Search project tags",
                systemImage: "tag",
                description: Text("Type a project name to search Phabricator tags.")
            )
        } else if isLoading && results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ContentUnavailableView(
                "Search failed",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if results.isEmpty {
            ContentUnavailableView(
                "No tags",
                systemImage: "tray",
                description: Text("Nothing matched \(debouncedQuery).")
            )
        } else {
            List(results, id: \.phid, selection: $selectedPHID) { project in
                row(for: project)
                    .tag(project.phid)
                    .contentShape(Rectangle())
                    .onTapGesture { commit(project) }
            }
            .focused($focused, equals: .list)
            .onKeyPress(.return) {
                commitSelection() ? .handled : .ignored
            }
            .onKeyPress(keys: [.tab]) { press in
                if press.modifiers.contains(.shift) {
                    focused = .search
                    return .handled
                }
                return .ignored
            }
        }
    }

    private func row(for project: PhabricatorProject) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.callout.weight(.medium))
                if let slug = project.slug, !slug.isEmpty {
                    Text("#\(slug)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if excludedPHIDs.contains(project.phid) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @discardableResult
    private func focusList() -> Bool {
        guard !results.isEmpty else { return false }
        if selectedPHID == nil { selectedPHID = results.first?.phid }
        focused = .list
        return true
    }

    @discardableResult
    private func commitSelection() -> Bool {
        let id = selectedPHID ?? results.first?.phid
        guard let id, let project = results.first(where: { $0.phid == id }) else {
            return false
        }
        commit(project)
        return true
    }

    private func commit(_ project: PhabricatorProject) {
        guard !excludedPHIDs.contains(project.phid) else { return }
        onPick(project)
        dismiss()
    }

    private func debounce() async {
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            debouncedQuery = query
        } catch {
        }
    }

    private func runSearch() async {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            loadError = nil
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let result = try await phab.client.searchProjects(.byName(trimmed, limit: 25))
            results = result.data.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch is CancellationError {
        } catch {
            results = []
            loadError = error.localizedDescription
        }
    }
}
