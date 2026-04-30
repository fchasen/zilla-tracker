//
//  MarkdownEditor.swift
//  Zilla
//
//  Thin wrapper around `Marginalia` that preserves the prior `MarkdownEditor`
//  call sites and adds the Zilla-specific link pickers (bug + user mention via
//  QuickSearchSheet, and Searchfox via SearchfoxPickerSheet) inline with
//  Marginalia's standard formatting toolbar.
//

import SwiftUI
import BugzillaKit
import Marginalia
import PhabricatorKit
import SearchfoxKit

enum TextDialect {
    case commonMark
    case remarkup
}

struct MarkdownEditor: View {
    @Binding var text: String
    var headerLabel: String? = nil
    var minHeight: CGFloat = 96
    var isDisabled: Bool = false
    var emptyPreviewLabel: String = "Nothing to preview yet."
    var dialect: TextDialect = .commonMark

    @State private var showingLinkPicker = false
    @State private var showingSearchfoxPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let headerLabel {
                Text(headerLabel)
                    .font(.headline)
            }
            Marginalia(text: $text)
                .marginaliaDialect(marginaliaDialect)
                .marginaliaPreviewRenderer(previewRenderer)
                .marginaliaConfiguration(toolbarConfiguration)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .disabled(isDisabled)
        }
        .sheet(isPresented: $showingLinkPicker) {
            QuickSearchSheet(
                onPickBug: { bugID in insertBugLink(bugID) },
                onPickUser: { user in insertUserMention(user) }
            )
        }
        .sheet(isPresented: $showingSearchfoxPicker) {
            SearchfoxPickerSheet { hit, symbol in
                insertSearchfoxLink(hit, symbol: symbol)
            }
        }
    }

    private var marginaliaDialect: Highlighter.Dialect {
        switch dialect {
        case .commonMark: return .commonMark
        case .remarkup:   return .remarkup
        }
    }

    private var previewRenderer: MarginaliaPreviewRenderer {
        { source, dialect in
            let normalized: String
            switch dialect {
            case .commonMark: normalized = source
            case .remarkup:   normalized = Remarkup.toCommonMark(source)
            }
            if let attr = try? AttributedString(markdown: normalized) {
                return attr
            }
            return AttributedString(normalized)
        }
    }

    /// Replaces Marginalia's plain `.action(.link)` with a custom item that
    /// opens the bug/user picker, and adds a Searchfox picker right after.
    /// Both sit inline with bold/italic/etc. so the toolbar stays a single row.
    private var toolbarConfiguration: Marginalia.Configuration {
        let replacements: [Marginalia.ToolbarItem] = [
            .custom(
                id: "linkPicker",
                label: "Insert bug or user link (⌘K)",
                systemImage: "link",
                shortcut: KeyboardShortcut("k", modifiers: .command),
                action: { showingLinkPicker = true }
            ),
            .custom(
                id: "searchfoxPicker",
                label: "Insert Searchfox link (⌘F)",
                systemImage: "magnifyingglass",
                shortcut: KeyboardShortcut("f", modifiers: .command),
                action: { showingSearchfoxPicker = true }
            )
        ]

        var items: [Marginalia.ToolbarItem] = []
        for item in Marginalia.Configuration.defaultToolbar {
            if case .action(.link) = item {
                items.append(contentsOf: replacements)
            } else {
                items.append(item)
            }
        }
        return Marginalia.Configuration(toolbar: items)
    }

    private func insertBugLink(_ bugID: Bug.ID) {
        let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)"
        text += "[bug \(bugID)](\(url))"
    }

    private func insertUserMention(_ user: User) {
        text += ":\(mentionHandle(for: user))"
    }

    private func mentionHandle(for user: User) -> String {
        if let nick = user.nick, !nick.isEmpty { return nick }
        let local = user.name.split(separator: "@").first.map(String.init) ?? user.name
        return local
    }

    private func insertSearchfoxLink(_ hit: SearchHit, symbol: String? = nil) {
        let label: String
        if let symbol, !symbol.isEmpty {
            label = symbol
        } else if hit.lineNumber > 0 {
            label = "\(hit.path)#L\(hit.lineNumber)"
        } else {
            label = hit.path
        }
        text += "[\(label)](\(hit.url))"
    }
}
