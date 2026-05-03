import SwiftUI
import BugzillaKit
import MarginaliaEditor
import PhabricatorKit
import SearchfoxKit
#if canImport(UIKit)
import UIKit
#endif

struct MarkdownEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 96
    var isDisabled: Bool = false
    var dialect: Dialect = .commonMark
    var bordered: Bool = true
    var showToolbar: Bool = true
    var autoFocus: Bool = false

    @Environment(\.zillaFontScale) private var fontScale

    @State private var controller: EditorController?
    @State private var showingLinkPicker = false
    @State private var showingSearchfoxPicker = false
    @State private var showingLinkInsert = false
    @State private var didAutoFocus = false

    var body: some View {
        Marginalia(text: $text)
            .dialect(dialect)
            .theme(.default(fontScale: fontScale))
            .configuration(Marginalia.Configuration(toolbar: showToolbar ? toolbar : [], minHeight: minHeight))
            .onMarginaliaControllerReady { c in
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

    private var toolbar: [Marginalia.ToolbarItem] {
        let leading: [Marginalia.ToolbarItem] = [
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
                systemImage: "ant",
                shortcut: KeyboardShortcut("k", modifiers: .command),
                topLevel: true,
                action: { showingLinkPicker = true }
            ),
            .divider,
        ]

        let linkInsert: Marginalia.ToolbarItem = .custom(
            id: "linkInsert",
            label: "Insert Link",
            systemImage: "link",
            action: { showingLinkInsert = true }
        )

        return leading + Marginalia.Configuration.defaultToolbar.replacing(.link, with: linkInsert)
    }

    private func insertBugLink(_ bugID: Bug.ID) {
        let url = "https://bugzilla.mozilla.org/show_bug.cgi?id=\(bugID)"
        controller?.insertLink(label: "bug \(bugID)", url: url)
    }

    private func insertMarkdownLink(label: String, url: String) {
        controller?.insertLink(label: label, url: url)
    }

    private func insertUserMention(_ user: User) {
        controller?.insert(text: ":\(mentionHandle(for: user))")
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
        controller?.insertLink(label: label, url: hit.url)
    }
}
