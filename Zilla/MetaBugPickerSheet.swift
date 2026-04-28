//
//  MetaBugPickerSheet.swift
//  Zilla
//

import SwiftUI
import SwiftData
import BugzillaKit

struct MetaBugPickerSheet: View {
    let component: FollowedComponent

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existing: [FollowedMetaBug]

    @State private var bugs: [Bug] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && bugs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ContentUnavailableView(
                        "Couldn't load meta bugs",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if bugs.isEmpty {
                    ContentUnavailableView(
                        "No open meta bugs",
                        systemImage: "tray",
                        description: Text("Nothing tagged \"meta\" in \(component.componentName).")
                    )
                } else {
                    List(filtered) { bug in
                        let already = isFollowed(bug.id)
                        Button {
                            if !already { add(bug) }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bug.summary)
                                        .foregroundStyle(.primary)
                                    Text("#\(bug.id) · \(bug.status)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if already {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(already)
                    }
                    .searchable(text: $search, placement: .toolbar, prompt: "Filter")
                }
            }
            .navigationTitle("Add Meta Bug")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 520)
        #endif
        .task { await load() }
    }

    private var filtered: [Bug] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return bugs }
        return bugs.filter {
            $0.summary.localizedCaseInsensitiveContains(trimmed) ||
            String($0.id).contains(trimmed)
        }
    }

    private func isFollowed(_ id: Int) -> Bool {
        existing.contains { $0.bugId == id }
    }

    private func add(_ bug: Bug) {
        let nextPosition = (component.metaBugs.map(\.position).max() ?? -1) + 1
        let meta = FollowedMetaBug(
            bugId: bug.id,
            summary: bug.summary,
            component: component,
            position: nextPosition
        )
        modelContext.insert(meta)
        dismiss()
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            var query = BugQuery(
                product: [component.product],
                component: [component.componentName],
                resolution: ["---"],
                keywords: ["meta"]
            )
            query.limit = 200
            query.includeFields = ["id", "summary", "status", "keywords"]
            let result = try await auth.client.searchBugs(query)
            bugs = result.bugs.sorted {
                $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
