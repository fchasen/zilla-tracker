//
//  SearchfoxPickerSheet.swift
//  Zilla
//

import SwiftUI
import SearchfoxKit

struct SearchfoxPickerSheet: View {
    let onPick: (SearchHit) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var results: [SearchHit] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedURL: String?

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case search, list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Files by path · @symbol for identifiers", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.top)
                    .submitLabel(.search)
                    .focused($focused, equals: .search)
                    .onSubmit { commitSelection() }
                    .onKeyPress(.tab) {
                        guard !results.isEmpty else { return .ignored }
                        if selectedURL == nil { selectedURL = results.first?.url }
                        focused = .list
                        return .handled
                    }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Insert Searchfox link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 520)
        #endif
        .task(id: query) { await debounce() }
        .task(id: debouncedQuery) { await runSearch() }
        .onAppear { focused = .search }
        .onChange(of: results) { _, new in
            if new.isEmpty {
                selectedURL = nil
            } else if !new.contains(where: { $0.url == selectedURL }) {
                selectedURL = new.first?.url
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Search Mozilla code",
                systemImage: "magnifyingglass",
                description: Text("Type a path fragment to find files. Prefix with @ to search identifiers (e.g. @AudioStream).")
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
                "No results",
                systemImage: "tray",
                description: Text("Nothing matched \(debouncedQuery).")
            )
        } else {
            List(results, id: \.url, selection: $selectedURL) { hit in
                row(for: hit)
                    .tag(hit.url)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onPick(hit)
                        dismiss()
                    }
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

    private func row(for hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(hit.path)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if hit.lineNumber > 0 {
                    Text("L\(hit.lineNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !hit.line.isEmpty {
                Text(hit.line)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @discardableResult
    private func commitSelection() -> Bool {
        let id = selectedURL ?? results.first?.url
        guard let id, let hit = results.first(where: { $0.url == id }) else {
            return false
        }
        onPick(hit)
        dismiss()
        return true
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
            if trimmed.hasPrefix("@") {
                let identifier = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                guard !identifier.isEmpty else {
                    results = []
                    return
                }
                results = try await searchIdentifiers(identifier: identifier, limit: 25)
            } else {
                results = try await searchFiles(path: trimmed, limit: 25)
            }
        } catch is CancellationError {
        } catch {
            results = []
            loadError = error.localizedDescription
        }
    }
}
