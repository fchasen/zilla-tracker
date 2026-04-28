//
//  MarkdownEditor.swift
//  Zilla
//

import SwiftUI
import BugzillaKit
import SearchfoxKit
import Textual

struct MarkdownEditor: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    var headerLabel: String? = nil
    var minHeight: CGFloat = 96
    var isDisabled: Bool = false
    var emptyPreviewLabel: String = "Nothing to preview yet."

    @State private var showPreview = false
    @State private var showingSearchfoxPicker = false
    @State private var showingLinkPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let headerLabel {
                    Text(headerLabel)
                        .font(.headline)
                }
                Spacer()
                if !showPreview {
                    formattingBar
                }
            }

            editorOrPreview

            HStack {
                Button {
                    showPreview.toggle()
                } label: {
                    Label(
                        showPreview ? "Edit" : "Preview",
                        systemImage: showPreview ? "pencil" : "eye"
                    )
                }
                .buttonStyle(.borderless)
                .disabled(isDisabled || (trimmedIsEmpty && !showPreview))
                Spacer()
            }
        }
        .sheet(isPresented: $showingSearchfoxPicker) {
            SearchfoxPickerSheet { hit, symbol in
                insertSearchfoxLink(hit, symbol: symbol)
            }
        }
        .sheet(isPresented: $showingLinkPicker) {
            QuickSearchSheet(
                onPickBug: { bugID in insertBugLink(bugID) },
                onPickUser: { user in insertUserMention(user) }
            )
        }
    }

    @ViewBuilder
    private var editorOrPreview: some View {
        if showPreview {
            ScrollView {
                Group {
                    if trimmedIsEmpty {
                        Text(emptyPreviewLabel)
                            .foregroundStyle(.secondary)
                    } else {
                        StructuredText(markdown: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: minHeight)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        } else {
            TextEditor(text: $text, selection: $selection)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .disabled(isDisabled)
                .onKeyPress(.return) {
                    handleReturnInList() ? .handled : .ignored
                }
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 2) {
            FormatButton(systemImage: "bold", help: "Bold (⌘B)", shortcut: KeyboardShortcut("b", modifiers: .command)) {
                wrap("**", "**", placeholder: "bold")
            }
            FormatButton(systemImage: "italic", help: "Italic (⌘I)", shortcut: KeyboardShortcut("i", modifiers: .command)) {
                wrap("*", "*", placeholder: "italic")
            }
            FormatButton(systemImage: "chevron.left.forwardslash.chevron.right", help: "Code block") {
                wrapCodeBlock()
            }
            FormatButton(systemImage: "link", help: "Link (⌘K)", shortcut: KeyboardShortcut("k", modifiers: .command)) {
                showingLinkPicker = true
            }
            FormatButton(systemImage: "list.bullet", help: "Bullet list") {
                prefixLines("- ")
            }
            FormatButton(systemImage: "list.number", help: "Numbered list") {
                numberedList()
            }
            FormatButton(systemImage: "text.quote", help: "Blockquote") {
                prefixLines("> ")
            }
            FormatButton(systemImage: "magnifyingglass", help: "Insert Searchfox link (⌘F)", shortcut: KeyboardShortcut("f", modifiers: .command)) {
                showingSearchfoxPicker = true
            }
        }
        .disabled(isDisabled)
    }

    private var trimmedIsEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func wrap(_ prefix: String, _ suffix: String, placeholder: String) {
        if let range = singleSelectionRange(), !range.isEmpty {
            let selected = String(text[range])
            text.replaceSubrange(range, with: prefix + selected + suffix)
        } else {
            text += prefix + placeholder + suffix
        }
    }

    private func insertBugLink(_ bugID: Bug.ID) {
        let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)"
        if let range = singleSelectionRange(), !range.isEmpty {
            let selected = String(text[range])
            text.replaceSubrange(range, with: "[\(selected)](\(url))")
        } else {
            text += "[bug \(bugID)](\(url))"
        }
    }

    private func insertUserMention(_ user: User) {
        let handle = ":\(mentionHandle(for: user))"
        if let range = singleSelectionRange(), !range.isEmpty {
            text.replaceSubrange(range, with: handle)
        } else {
            text += handle
        }
    }

    private func mentionHandle(for user: User) -> String {
        if let nick = user.nick, !nick.isEmpty { return nick }
        let local = user.name.split(separator: "@").first.map(String.init) ?? user.name
        return local
    }

    private func insertSearchfoxLink(_ hit: SearchHit, symbol: String? = nil) {
        let fallbackLabel: String
        if let symbol, !symbol.isEmpty {
            fallbackLabel = symbol
        } else if hit.lineNumber > 0 {
            fallbackLabel = "\(hit.path)#L\(hit.lineNumber)"
        } else {
            fallbackLabel = hit.path
        }
        if let range = singleSelectionRange() {
            if range.isEmpty {
                text.replaceSubrange(range, with: "[\(fallbackLabel)](\(hit.url))")
            } else {
                let selected = String(text[range])
                text.replaceSubrange(range, with: "[\(selected)](\(hit.url))")
            }
        } else {
            text += "[\(fallbackLabel)](\(hit.url))"
        }
    }

    private func wrapCodeBlock() {
        let leadIn = text.hasSuffix("\n") || text.isEmpty ? "" : "\n"
        if let range = singleSelectionRange(), !range.isEmpty {
            var selected = String(text[range])
            if selected.hasSuffix("\n") { selected.removeLast() }
            let opening = (range.lowerBound == text.startIndex || text[text.index(before: range.lowerBound)] == "\n") ? "" : "\n"
            text.replaceSubrange(range, with: "\(opening)```\n\(selected)\n```\n")
        } else {
            text += "\(leadIn)```\ncode\n```\n"
        }
    }

    private func prefixLines(_ marker: String) {
        if let range = singleSelectionRange(), !range.isEmpty {
            let block = String(text[range])
            let prefixed = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { marker + $0 }
                .joined(separator: "\n")
            text.replaceSubrange(range, with: prefixed)
        } else {
            text += (text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + marker
        }
    }

    private func numberedList() {
        if let range = singleSelectionRange(), !range.isEmpty {
            let block = String(text[range])
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            let numbered = lines.enumerated()
                .map { index, line in "\(index + 1). \(line)" }
                .joined(separator: "\n")
            text.replaceSubrange(range, with: numbered)
        } else {
            text += (text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + "1. "
        }
    }

    private func handleReturnInList() -> Bool {
        guard let cursor = currentCursor() else { return false }

        let beforeCursor = text[..<cursor]
        let lineStart = beforeCursor.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let currentLine = String(text[lineStart..<cursor])

        guard let info = listMarker(of: currentLine) else { return false }

        let content = currentLine.dropFirst(info.marker.count)
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            text.removeSubrange(lineStart..<cursor)
            let newCursor = text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: lineStart))
            selection = TextSelection(insertionPoint: newCursor)
            return true
        } else {
            let nextMarker = info.kind.nextMarker(after: info.marker)
            let inserted = "\n" + nextMarker
            let cursorOffset = text.distance(from: text.startIndex, to: cursor)
            text.insert(contentsOf: inserted, at: cursor)
            let newCursor = text.index(text.startIndex, offsetBy: cursorOffset + inserted.count)
            selection = TextSelection(insertionPoint: newCursor)
            return true
        }
    }

    private func currentCursor() -> String.Index? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return range.upperBound
        case .multiSelection(let ranges):
            return ranges.ranges.first?.upperBound
        @unknown default:
            return nil
        }
    }

    private enum ListKind {
        case bullet
        case numbered

        func nextMarker(after marker: String) -> String {
            switch self {
            case .bullet:
                return "- "
            case .numbered:
                let digits = marker.dropLast(2)
                let n = Int(digits) ?? 1
                return "\(n + 1). "
            }
        }
    }

    private func listMarker(of line: String) -> (marker: String, kind: ListKind)? {
        if line.hasPrefix("- ") {
            return (marker: "- ", kind: .bullet)
        }
        if let match = line.range(of: #"^\d+\. "#, options: .regularExpression) {
            return (marker: String(line[match]), kind: .numbered)
        }
        return nil
    }

    private func singleSelectionRange() -> Range<String.Index>? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return range
        case .multiSelection(let ranges):
            return ranges.ranges.first
        @unknown default:
            return nil
        }
    }
}

struct FormatButton: View {
    let systemImage: String
    let help: String
    var shortcut: KeyboardShortcut? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
        .modifier(OptionalKeyboardShortcut(shortcut: shortcut))
    }
}

struct OptionalKeyboardShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}
