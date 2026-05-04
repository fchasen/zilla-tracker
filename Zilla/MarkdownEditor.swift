import SwiftUI
import BugzillaKit
import SwiftProse
import PhabricatorKit
import SearchfoxKit
import FolioCodeView
import FolioHighlight
#if canImport(UIKit)
import UIKit
#endif

enum MarkdownEditorMode: String, CaseIterable {
    case rich
    case source
}

struct MarkdownEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 96
    var isDisabled: Bool = false
    var bordered: Bool = true
    var showToolbar: Bool = true
    var autoFocus: Bool = false

    @Environment(\.zillaFontScale) private var fontScale
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("zilla.markdown.mode") private var mode: MarkdownEditorMode = .rich

    @State private var controller: EditorController?
    @State private var showingLinkPicker = false
    @State private var showingSearchfoxPicker = false
    @State private var showingLinkInsert = false
    @State private var didAutoFocus = false
    @State private var pendingInsertionSelection: NSRange?

    var body: some View {
        Group {
            switch mode {
            case .rich:
                richEditor
            case .source:
                sourceEditor
            }
        }
        .disabled(isDisabled)
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

    private var richEditor: some View {
        SwiftProseEditor(text: $text)
            .theme(.default(fontScale: fontScale))
            .configuration(SwiftProseEditor.Configuration(toolbar: showToolbar ? richToolbar : [], minHeight: minHeight))
            .onProseControllerReady { c in
                controller = c
                if autoFocus { focusHostTextView() }
            }
            .frame(minHeight: minHeight)
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
            }
    }

    private var sourceEditor: some View {
        VStack(spacing: 0) {
            if showToolbar {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Spacer()
                        ControlGroup {
                            Button {
                                mode = .rich
                            } label: {
                                Image(systemName: "eye")
                                    .frame(width: toolbarButtonWidth, height: toolbarButtonHeight)
                            }
                            .help("Switch to rich editor")
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(6)
            }
            CodeEditorRepresentable(
                text: $text,
                language: .markdown,
                theme: colorScheme == .dark ? .dark : .light,
                font: sourceFont,
                fitsContent: true,
                minHeight: minHeight
            )
        }
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private var toolbarButtonWidth: CGFloat {
        #if os(iOS)
        return 36
        #else
        return 28
        #endif
    }

    private var toolbarButtonHeight: CGFloat {
        #if os(iOS)
        return 32
        #else
        return 24
        #endif
    }

    private var sourceFont: PlatformFont {
        let size = PlatformFont.systemFontSize * max(fontScale, 0.1)
        return PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private var richToolbar: [SwiftProseEditor.ToolbarItem] {
        let leading: [SwiftProseEditor.ToolbarItem] = [
            .custom(
                id: "searchfoxPicker",
                label: "Searchfox",
                systemImage: "magnifyingglass",
                shortcut: KeyboardShortcut("f", modifiers: .command),
                topLevel: true,
                action: {
                    capturePendingSelection()
                    showingSearchfoxPicker = true
                }
            ),
            .custom(
                id: "bugPicker",
                label: "Insert Bug",
                systemImage: "ant",
                shortcut: KeyboardShortcut("k", modifiers: .command),
                topLevel: true,
                action: {
                    capturePendingSelection()
                    showingLinkPicker = true
                }
            ),
            .divider,
        ]

        let linkInsert: SwiftProseEditor.ToolbarItem = .custom(
            id: "linkInsert",
            label: "Insert Link",
            systemImage: "link",
            action: {
                capturePendingSelection()
                showingLinkInsert = true
            }
        )

        let modeToggle: SwiftProseEditor.ToolbarItem = .custom(
            id: "modeToggle",
            label: "Source",
            systemImage: "chevron.left.forwardslash.chevron.right",
            topLevel: true,
            action: {
                if let md = controller?.markdown() { text = md }
                mode = .source
            }
        )

        return leading
            + SwiftProseEditor.Configuration.defaultToolbar.replacing(.link, with: linkInsert)
            + [.spacer, modeToggle]
    }

    private func insertBugLink(_ bugID: Bug.ID) {
        let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)"
        restorePendingSelection()
        controller?.insertLink(label: "bug \(bugID)", url: url)
        pushMarkdownToBinding()
    }

    private func insertMarkdownLink(label: String, url: String) {
        restorePendingSelection()
        controller?.insertLink(label: label, url: url)
        pushMarkdownToBinding()
    }

    private func insertUserMention(_ user: User) {
        restorePendingSelection()
        controller?.insert(text: ":\(mentionHandle(for: user))")
        pushMarkdownToBinding()
    }

    private func mentionHandle(for user: User) -> String {
        if let nick = user.nick, !nick.isEmpty { return nick }
        let local = user.name.split(separator: "@").first.map(String.init) ?? user.name
        return local
    }

    private func focusHostTextView() {
        #if canImport(UIKit)
        guard !didAutoFocus else { return }
        Task { @MainActor in
            for _ in 0..<10 {
                if let view = controller?.hostTextView as? UIView, view.window != nil {
                    view.becomeFirstResponder()
                    didAutoFocus = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        #endif
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
        restorePendingSelection()
        controller?.insertLink(label: label, url: hit.url)
        pushMarkdownToBinding()
    }

    private func capturePendingSelection() {
        pendingInsertionSelection = controller?.currentSelection
    }

    private func restorePendingSelection() {
        guard let selection = pendingInsertionSelection else { return }
        controller?.setSelection(selection)
        pendingInsertionSelection = nil
    }

    private func pushMarkdownToBinding() {
        guard let md = controller?.markdown(), md != text else { return }
        text = md
    }
}
