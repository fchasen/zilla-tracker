//
//  SearchfoxPickerSheet.swift
//  Zilla
//

import SwiftUI
import SearchfoxKit

struct SearchfoxPickerSheet: View {
    let onPick: (SearchHit, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var debouncedQuery: String = ""
    @State private var results: [SearchHit] = []
    @State private var resultSymbol: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedURL: String?

    @FocusState private var searchFocused: Bool

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
        .onAppear { searchFocused = true }
        .onChange(of: results) { _, new in
            if new.isEmpty {
                selectedURL = nil
            } else if !new.contains(where: { $0.url == selectedURL }) {
                selectedURL = new.first?.url
            }
        }
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Files by path · @symbol for identifiers", text: $query)
                .textFieldStyle(.plain)
                .scaledFont(.title3)
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { commitSelection() }
                .onKeyPress(.return) { commitSelection() ? .handled : .ignored }
                .onKeyPress(.upArrow) { moveSelection(-1) ? .handled : .ignored }
                .onKeyPress(.downArrow) { moveSelection(1) ? .handled : .ignored }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results, id: \.url) { hit in
                            row(for: hit)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(rowHighlight(for: hit.url))
                                .contentShape(Rectangle())
                                .id(hit.url)
                                .onTapGesture {
                                    onPick(hit, resultSymbol)
                                    dismiss()
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedURL) { _, new in
                    if let new { withAnimation(.linear(duration: 0.05)) { proxy.scrollTo(new, anchor: .center) } }
                }
            }
        }
    }

    @ViewBuilder
    private func rowHighlight(for url: String) -> some View {
        if selectedURL == url {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
                .padding(.horizontal, 8)
        }
    }

    private func row(for hit: SearchHit) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: fileIcon(for: hit.path))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(hit.path)
                        .scaledFont(.callout)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 8)
                    if hit.lineNumber > 0 {
                        Text("L\(hit.lineNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if !hit.line.isEmpty {
                    Text(hit.line)
                        .scaledFont(.footnote, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileIcon(for path: String) -> String {
        let name = (path as NSString).lastPathComponent.lowercased()

        if name == "moz.build" || name == "makefile" || name.hasSuffix(".mozbuild") {
            return "hammer"
        }

        let ext: String = {
            if let dot = name.lastIndex(of: ".") {
                return String(name[name.index(after: dot)...])
            }
            return ""
        }()

        switch ext {
        case "h", "hpp", "hh", "hxx":
            return "chevron.left.forwardslash.chevron.right"
        case "c", "cc", "cpp", "cxx", "m", "mm":
            return "chevron.left.forwardslash.chevron.right"
        case "swift", "rs", "go", "java", "kt", "scala":
            return "chevron.left.forwardslash.chevron.right"
        case "js", "mjs", "cjs", "jsm", "ts", "tsx", "jsx":
            return "chevron.left.forwardslash.chevron.right"
        case "py", "rb", "pl", "lua":
            return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh", "fish":
            return "terminal"
        case "html", "htm", "xhtml", "xml", "xul", "xbl", "svg":
            return "globe"
        case "css", "scss", "sass", "less":
            return "paintbrush"
        case "json", "yaml", "yml", "toml", "ini", "cfg", "conf", "plist":
            return "gearshape"
        case "md", "markdown", "rst", "txt":
            return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "ico", "bmp", "tiff":
            return "photo"
        case "mp4", "mov", "webm", "mkv", "avi":
            return "film"
        case "mp3", "wav", "ogg", "flac", "aac":
            return "speaker.wave.2"
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar":
            return "doc.zipper"
        case "pdf":
            return "doc.richtext"
        case "patch", "diff":
            return "arrow.triangle.branch"
        default:
            return ext.isEmpty ? "doc" : "doc.text"
        }
    }

    @discardableResult
    private func moveSelection(_ delta: Int) -> Bool {
        guard !results.isEmpty else { return false }
        let urls = results.map { $0.url }
        let currentIdx = urls.firstIndex(of: selectedURL ?? "") ?? -1
        let target: Int
        if currentIdx < 0 {
            target = delta > 0 ? 0 : urls.count - 1
        } else {
            target = max(0, min(urls.count - 1, currentIdx + delta))
        }
        selectedURL = urls[target]
        return true
    }

    @discardableResult
    private func commitSelection() -> Bool {
        let id = selectedURL ?? results.first?.url
        guard let id, let hit = results.first(where: { $0.url == id }) else {
            return false
        }
        onPick(hit, resultSymbol)
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
            resultSymbol = nil
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
                    resultSymbol = nil
                    return
                }
                results = try await searchIdentifiers(identifier: identifier, limit: 25)
                resultSymbol = identifier
            } else {
                results = try await searchFiles(path: trimmed, limit: 25)
                resultSymbol = nil
            }
        } catch is CancellationError {
        } catch {
            results = []
            resultSymbol = nil
            loadError = error.localizedDescription
        }
    }
}
