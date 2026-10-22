//
//  TagTokens.swift
//  Zilla
//

import SwiftUI
import BugzillaKit

struct TagSuggestion: Identifiable, Hashable {
    let name: String
    var detail: String = ""

    var id: String { name.lowercased() }

    static func matches(
        _ suggestions: [TagSuggestion],
        query: String,
        excluding excluded: [String],
        limit: Int = 60
    ) -> [TagSuggestion] {
        let taken = Set(excluded.map { $0.lowercased() })
        let available = suggestions.filter { !taken.contains($0.id) }
        let needle = normalizedQuery(query)
        guard !needle.isEmpty else { return Array(available.prefix(limit)) }
        var prefixed: [TagSuggestion] = []
        var contained: [TagSuggestion] = []
        var described: [TagSuggestion] = []
        for suggestion in available {
            if suggestion.id.hasPrefix(needle) {
                prefixed.append(suggestion)
            } else if suggestion.id.contains(needle) {
                contained.append(suggestion)
            } else if suggestion.detail.lowercased().contains(needle) {
                described.append(suggestion)
            }
        }
        return Array((prefixed + contained + described).prefix(limit))
    }

    static func normalizedQuery(_ query: String) -> String {
        Whiteboard.normalize(query).lowercased()
    }
}

struct TagChipLabel: View {
    let text: String
    var monospaced = false

    var body: some View {
        Text(text)
            .scaledFont(.caption, weight: .semibold, design: monospaced ? .monospaced : .default)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .contentShape(Capsule())
    }
}

struct TagChip: View {
    let text: String
    var monospaced = false
    var help: String?
    var onRemove: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .scaledFont(.caption, weight: .semibold, design: monospaced ? .monospaced : .default)
            if let onRemove, isEnabled {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .scaledFont(.caption2, weight: .bold)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(text)")
                .accessibilityLabel("Remove \(text)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.15), in: Capsule())
        .contentShape(Capsule())
        .help(help ?? text)
        .contextMenu {
            Button("Copy") { copyToPasteboard(text) }
            if let onRemove {
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            }
        }
    }
}

struct TagTokenList: View {
    let tags: [String]
    let addLabel: String
    let popoverTitle: String
    let placeholder: String
    let suggestions: [TagSuggestion]
    var allowsCustom = false
    var monospaced = false
    var isLoading = false
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var isAdding = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let details = Dictionary(
            suggestions.map { ($0.id, $0.detail) },
            uniquingKeysWith: { first, _ in first }
        )
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tags, id: \.self) { tag in
                TagChip(
                    text: tag,
                    monospaced: monospaced,
                    help: details[tag.lowercased()].flatMap { $0.isEmpty ? nil : $0 },
                    onRemove: { onRemove(tag) }
                )
            }
            if isEnabled {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                        .scaledFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.35)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(addLabel)
                .accessibilityLabel(addLabel)
                .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                    TagSuggestionPopover(
                        title: popoverTitle,
                        placeholder: placeholder,
                        suggestions: suggestions,
                        excluded: tags,
                        allowsCustom: allowsCustom,
                        monospaced: monospaced,
                        isLoading: isLoading,
                        onPick: onAdd
                    )
                }
            }
        }
    }
}

struct TagSuggestionPopover: View {
    #if os(macOS)
    private static let popoverWidth: CGFloat = 300
    private static let resultsMaxHeight: CGFloat = 240
    #endif

    let title: String
    let placeholder: String
    let suggestions: [TagSuggestion]
    let excluded: [String]
    var allowsCustom = false
    var monospaced = false
    var isLoading = false
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var selectedID: String?
    @FocusState private var isFocused: Bool

    private struct Row: Identifiable {
        let id: String
        let name: String
        let detail: String
        let isCustom: Bool
    }

    private static let customRowID = "\u{0}custom"

    private var rows: [Row] {
        let matches = TagSuggestion.matches(suggestions, query: query, excluding: excluded)
        var rows = matches.map { Row(id: $0.id, name: $0.name, detail: $0.detail, isCustom: false) }
        if let custom = customValue(matches: matches) {
            rows.append(Row(id: Self.customRowID, name: custom, detail: "", isCustom: true))
        }
        return rows
    }

    private func customValue(matches: [TagSuggestion]) -> String? {
        guard allowsCustom else { return nil }
        let value = Whiteboard.normalize(query)
        guard !value.isEmpty,
              !excluded.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }),
              !matches.contains(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame })
        else { return nil }
        return value
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .scaledFont(.caption2, weight: .semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            TextField(placeholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .scaledFont(.callout, design: monospaced ? .monospaced : .default)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { commitSelection(in: rows) }
                .onKeyPress(.return) { commitSelection(in: rows) ? .handled : .ignored }
                .onKeyPress(.upArrow) { moveSelection(-1, in: rows) ? .handled : .ignored }
                .onKeyPress(.downArrow) { moveSelection(1, in: rows) ? .handled : .ignored }
                .onChange(of: query) { syncSelection() }
            if isLoading && suggestions.isEmpty && !allowsCustom {
                ProgressView().controlSize(.small)
            } else if rows.isEmpty {
                Text(query.isEmpty ? "No suggestions" : "No matches")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { row in
                                Button {
                                    pick(row.name)
                                } label: {
                                    rowLabel(row)
                                }
                                .buttonStyle(.plain)
                                .id(row.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: selectedID) { _, new in
                        if let new {
                            proxy.scrollTo(new, anchor: .center)
                        }
                    }
                    #if os(iOS)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    #else
                    .frame(maxHeight: Self.resultsMaxHeight)
                    #endif
                }
            }
        }
        .padding(12)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: Self.popoverWidth)
        #endif
        .onAppear {
            isFocused = true
            syncSelection()
        }
    }

    private func rowLabel(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if row.isCustom {
                Label {
                    Text("Add “\(row.name)”")
                } icon: {
                    Image(systemName: "plus.circle")
                }
                .scaledFont(.callout)
            } else {
                Text(row.name)
                    .scaledFont(.callout, design: monospaced ? .monospaced : .default)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background {
            if selectedID == row.id {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
    }

    private func pick(_ value: String) {
        onPick(value)
        query = ""
        syncSelection()
    }

    @discardableResult
    private func moveSelection(_ delta: Int, in rows: [Row]) -> Bool {
        guard !rows.isEmpty else { return false }
        let ids = rows.map(\.id)
        let current = selectedID.flatMap { ids.firstIndex(of: $0) }
        let target: Int
        if let current {
            target = max(0, min(ids.count - 1, current + delta))
        } else {
            target = delta > 0 ? 0 : ids.count - 1
        }
        selectedID = ids[target]
        return true
    }

    @discardableResult
    private func commitSelection(in rows: [Row]) -> Bool {
        guard let row = rows.first(where: { $0.id == selectedID }) else { return false }
        pick(row.name)
        return true
    }

    private func syncSelection() {
        let rows = rows
        let needle = TagSuggestion.normalizedQuery(query)
        if allowsCustom, !needle.isEmpty,
           let custom = rows.first(where: \.isCustom),
           !rows.contains(where: { !$0.isCustom && $0.id.hasPrefix(needle) }) {
            selectedID = custom.id
        } else {
            selectedID = rows.first?.id
        }
    }
}

struct KeywordTokenList: View {
    let keywords: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth

    var body: some View {
        let catalog = workspace.keywordCatalog
        TagTokenList(
            tags: keywords,
            addLabel: "Add keyword",
            popoverTitle: "Add Keyword",
            placeholder: "Search keywords…",
            suggestions: catalog.map { TagSuggestion(name: $0.name, detail: $0.description) },
            allowsCustom: catalog.isEmpty,
            isLoading: catalog.isEmpty,
            onAdd: onAdd,
            onRemove: onRemove
        )
        .task {
            await workspace.loadKeywords(using: auth.client)
        }
    }
}

struct WhiteboardTokenList: View {
    let whiteboard: String
    let onChange: (String) -> Void

    @Environment(Workspace.self) private var workspace

    var body: some View {
        let board = Whiteboard(whiteboard)
        TagTokenList(
            tags: board.tags,
            addLabel: "Add whiteboard tag",
            popoverTitle: "Add Tag",
            placeholder: "tag",
            suggestions: workspace.whiteboardTagHistory.tags.map { TagSuggestion(name: $0) },
            allowsCustom: true,
            monospaced: true,
            onAdd: { value in
                var updated = board
                updated.add(value)
                workspace.whiteboardTagHistory.record(value)
                onChange(updated.rawValue)
            },
            onRemove: { tag in
                var updated = board
                updated.remove(tag)
                onChange(updated.rawValue)
            }
        )
    }
}
