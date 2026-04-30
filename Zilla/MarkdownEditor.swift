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
    @State private var showingLinkInsert = false
    @AppStorage("MarkdownEditor.toolbarVisible") private var toolbarVisible = true

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
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .disabled(isDisabled)
                .contextMenu {
                    Toggle(isOn: $toolbarVisible) {
                        Label("Show Toolbar", systemImage: "richtext.page")
                    }
                }
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
        .sheet(isPresented: $showingLinkInsert) {
            LinkInsertSheet { label, url in
                insertMarkdownLink(label: label, url: url)
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

    private var toolbarConfiguration: Marginalia.Configuration {
        let menuItems: [Marginalia.ContextMenuItem] = [
            .init(
                title: "Show Toolbar",
                systemImage: "richtext.page",
                isOn: toolbarVisible,
                action: { toolbarVisible.toggle() }
            )
        ]

        guard toolbarVisible else {
            return Marginalia.Configuration(toolbar: [], contextMenuItems: menuItems)
        }

        let toolbar: [Marginalia.ToolbarItem] = [
            .custom(
                id: "searchfoxPicker",
                label: "Searchfox",
                systemImage: "magnifyingglass",
                shortcut: KeyboardShortcut("f", modifiers: .command),
                topLevel: true,
                action: { showingSearchfoxPicker = true }
            ),
            .custom(
                id: "bugPicker",
                label: "Insert Bug",
                systemImage: "ladybug",
                shortcut: KeyboardShortcut("k", modifiers: .command),
                topLevel: true,
                action: { showingLinkPicker = true }
            ),
            .divider,
            .action(.bold),
            .action(.italic),
            .action(.strikethrough),
            .divider,
            .action(.heading(level: 1)),
            .action(.heading(level: 2)),
            .action(.heading(level: 3)),
            .divider,
            .action(.unorderedList),
            .action(.orderedList),
            .action(.taskList),
            .action(.blockquote),
            .divider,
            .action(.codeSpan),
            .action(.codeBlock),
            .action(.horizontalRule),
            .divider,
            .custom(
                id: "linkInsert",
                label: "Insert Link",
                systemImage: "link",
                action: { showingLinkInsert = true }
            ),
            .spacer,
            .action(.togglePreview)
        ]

        return Marginalia.Configuration(toolbar: toolbar, contextMenuItems: menuItems)
    }

    private func insertBugLink(_ bugID: Bug.ID) {
        let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)"
        text += "[bug \(bugID)](\(url))"
    }

    private func insertMarkdownLink(label: String, url: String) {
        text += "[\(label)](\(url))"
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
