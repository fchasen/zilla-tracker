import Foundation
import SwiftUI
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

public struct MarkdownTextEditor: View {
    @Binding public var text: String

    @Environment(\.markdownEditorConfiguration) private var configuration
    @Environment(\.markdownEditorTheme) private var theme
    @Environment(\.markdownInlineContentProvider) private var inlineProvider
    @Environment(\.markdownInlineContentRules) private var inlineContentRules
    @Environment(\.markdownEditorReady) private var onEditorReady
    @Environment(\.isEnabled) private var isEnabled

    @AppStorage(MarkdownTextEditor.toolbarVisibleKey) private var toolbarVisible = true
    @State private var hosting = EditorHosting()

    public static let toolbarVisibleKey = "markdowneditorkit.toolbarVisible"

    public init(text: Binding<String>) {
        self._text = text
    }

    static func showsToolbar(for configuration: Configuration) -> Bool {
        !configuration.toolbar.isEmpty
    }

    static func effectiveIsEditable(for configuration: Configuration, isEnabled: Bool) -> Bool {
        configuration.isEditable && isEnabled
    }

    private var effectiveIsEditable: Bool {
        Self.effectiveIsEditable(for: configuration, isEnabled: isEnabled)
    }

    public var body: some View {
        let controller = hosting.ensureController(
            markdown: text,
            theme: theme,
            inlineContentRules: inlineContentRules,
            inlineContentProvider: inlineProvider,
            allowsCheckboxToggle: configuration.allowsCheckboxToggle
        )
        hosting.trackedActions = configuration.toolbar.actions
        return VStack(alignment: .leading, spacing: 0) {
            if toolbarVisible, Self.showsToolbar(for: configuration) {
                EditorToolbar(
                    items: configuration.toolbar,
                    perform: { EditorToolbarActions.perform($0, controller: controller) },
                    canPerform: { hosting.canPerform($0) },
                    isActive: { hosting.isActive($0) },
                    isEnabled: effectiveIsEditable
                )
                .padding(6)
            }
            editorBody(controller: controller)
        }
        .onAppear {
            hosting.applyInlineContent(rules: inlineContentRules, provider: inlineProvider)
            hosting.refreshToolbarState()
            onEditorReady?(controller)
        }
        .onChange(of: theme) { _, newTheme in
            controller.theme = newTheme
        }
        .onChange(of: configuration.allowsCheckboxToggle) { _, value in
            controller.allowsCheckboxToggle = value
        }
        .onChange(of: effectiveIsEditable) { _, _ in
            hosting.scheduleToolbarRefresh()
        }
        .onChange(of: configuration.toolbar.actions.map(\.stableID)) { _, _ in
            hosting.scheduleToolbarRefresh()
        }
        .onChange(of: inlineContentRules.map(\.id)) { _, _ in
            hosting.applyInlineContent(rules: inlineContentRules, provider: inlineProvider)
        }
    }

    @ViewBuilder
    private func editorBody(controller: MarkdownEditorController) -> some View {
        #if os(macOS)
        MarkdownTextViewMac(
            controller: controller,
            text: $text,
            sizing: configuration.sizing,
            minHeight: configuration.minHeight,
            contextMenuItems: contextMenuItems(),
            spellChecking: configuration.spellChecking,
            isEditable: effectiveIsEditable,
            onSubmit: configuration.onSubmit
        )
        .modifier(SizingFrame(sizing: configuration.sizing))
        #else
        MarkdownTextViewIOS(
            controller: controller,
            text: $text,
            sizing: configuration.sizing,
            minHeight: configuration.minHeight,
            editMenuBuilder: editMenuBuilder(controller: controller),
            spellChecking: configuration.spellChecking,
            isEditable: effectiveIsEditable,
            onSubmit: configuration.onSubmit
        )
        .modifier(SizingFrame(sizing: configuration.sizing))
        #endif
    }

    #if os(macOS)
    private func contextMenuItems() -> [EditorContextMenuItem] {
        var items: [EditorContextMenuItem] = []
        if Self.showsToolbar(for: configuration) {
            let visible = toolbarVisible
            items.append(EditorContextMenuItem(
                title: "Show Toolbar",
                systemImage: "richtext.page",
                isOn: visible,
                action: { toolbarVisible.toggle() }
            ))
        }
        items.append(contentsOf: configuration.contextMenuItems.map {
            EditorContextMenuItem(title: $0.title, systemImage: $0.systemImage, isOn: $0.isOn, action: $0.action)
        })
        return items
    }
    #endif

    #if os(iOS)
    private func editMenuBuilder(controller: MarkdownEditorController) -> MarkdownTextViewIOS.EditMenuBuilder? {
        let toolbar = configuration.toolbar
        guard !toolbar.isEmpty else { return nil }
        return { [weak controller] _, suggested in
            guard let controller else { return UIMenu(children: suggested) }
            return Self.editMenu(toolbar: toolbar, suggested: suggested, controller: controller)
        }
    }

    @MainActor
    static func editMenu(
        toolbar: [ToolbarItem],
        suggested: [UIMenuElement],
        controller: MarkdownEditorController
    ) -> UIMenu {
        var topLevel: [UIMenuElement] = []
        var sections: [UIMenuElement] = []
        var current: [UIMenuElement] = []
        func flush() {
            if !current.isEmpty {
                sections.append(UIMenu(title: "", options: .displayInline, children: current))
                current.removeAll()
            }
        }
        for item in toolbar {
            switch item {
            case .action(let action):
                let element = UIAction(
                    title: action.title,
                    image: UIImage(systemName: action.systemImage),
                    attributes: controller.canPerform(action) ? [] : .disabled,
                    state: controller.isActive(action) ? .on : .off
                ) { [weak controller] _ in
                    guard let controller else { return }
                    EditorToolbarActions.perform(action, controller: controller)
                }
                current.append(element)
            case .custom(_, let label, let symbol, _, let isTopLevel, let custom):
                let element = UIAction(title: label, image: UIImage(systemName: symbol)) { _ in custom() }
                if isTopLevel {
                    flush()
                    topLevel.append(element)
                } else {
                    current.append(element)
                }
            case .menu(_, let label, let symbol, let isTopLevel, let entries):
                let submenu = UIMenu(
                    title: label,
                    image: UIImage(systemName: symbol),
                    children: entries.map { entry in
                        UIAction(
                            title: entry.title,
                            image: entry.systemImage.flatMap { UIImage(systemName: $0) }
                        ) { _ in entry.action() }
                    }
                )
                if isTopLevel {
                    flush()
                    topLevel.append(submenu)
                } else {
                    current.append(submenu)
                }
            case .divider, .spacer:
                flush()
            }
        }
        flush()
        var children = suggested
        children.append(contentsOf: topLevel)
        if !sections.isEmpty {
            children.append(UIMenu(
                title: "Format",
                image: UIImage(systemName: "textformat"),
                children: sections
            ))
        }
        return UIMenu(children: children)
    }
    #endif
}

private struct SizingFrame: ViewModifier {
    let sizing: EditorSizing

    func body(content: Content) -> some View {
        switch sizing {
        case .fitsContent:
            content.frame(maxWidth: .infinity)
        case .fillContainer:
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
