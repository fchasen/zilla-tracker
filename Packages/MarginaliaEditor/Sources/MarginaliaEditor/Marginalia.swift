import Foundation
import SwiftUI
@_exported import MarginaliaSyntax
@_exported import MarginaliaRendering
@_exported import MarginaliaView

#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// SwiftUI live Markdown editor.
///
/// ```swift
/// Marginalia(text: $draft.bugDescription, selection: $selection)
///     .dialect(.commonMark)
///     .inlineContentProvider { content in
///         MarginaliaChip.attachment(for: content)
///     }
///     .frame(minHeight: 240)
/// ```
///
/// `Marginalia` is intentionally a **value** view: bindings come in via
/// `init`, configuration comes in via the editor modifiers (which
/// flow through SwiftUI's environment). Everything else (the `EditorController`,
/// the TextKit 2 stack, the parser, the highlighter) is an implementation
/// detail held in `@StateObject` storage so it survives view recreation.
public struct Marginalia: View {
    @Binding public var text: String
    @Binding public var selection: NSRange

    @Environment(\.marginaliaConfiguration) private var configuration
    @Environment(\.marginaliaDialect) private var dialect
    @Environment(\.marginaliaTheme) private var theme
    @Environment(\.marginaliaInlineContentProvider) private var inlineProvider

    @AppStorage("marginalia.toolbarVisible") private var toolbarVisible = true
    @AppStorage("marginalia.mode") private var modeRawValue: String = MarginaliaMode.wysiwyg.rawValue
    @StateObject private var hosting = MarginaliaHosting()

    private var mode: MarginaliaMode {
        MarginaliaMode(rawValue: modeRawValue) ?? .wysiwyg
    }

    public init(text: Binding<String>, selection: Binding<NSRange> = .constant(NSRange(location: 0, length: 0))) {
        self._text = text
        self._selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if toolbarVisible, !configuration.toolbar.isEmpty || !configuration.statusItems.isEmpty {
                HStack(spacing: 12) {
                    if !configuration.toolbar.isEmpty {
                        MarginaliaToolbar(
                            items: configuration.toolbar + [.spacer, modeToggleItem],
                            perform: { action in
                                guard let controller = hosting.controller else { return }
                                MarginaliaToolbarActions.perform(
                                    action,
                                    controller: controller,
                                    text: $text
                                )
                            }
                        )
                    }
                    if !configuration.statusItems.isEmpty {
                        Spacer()
                        MarginaliaStatusBar(
                            items: configuration.statusItems,
                            text: text,
                            selection: selection
                        )
                    }
                }
                .padding(6)
            }
            editorBody
        }
        .onAppear {
            hosting.ensureController(initialText: text, dialect: dialect, theme: theme, mode: mode)
            if let controller = hosting.controller {
                if controller.text != text { controller.setText(text) }
                controller.mode = mode
            }
        }
        .onChange(of: dialect) { _, newDialect in
            hosting.controller?.dialect = newDialect
        }
        .onChange(of: theme) { _, newTheme in
            hosting.controller?.theme = newTheme
        }
        .onChange(of: modeRawValue) { _, _ in
            hosting.controller?.mode = mode
        }
    }

    private var modeToggleItem: Marginalia.ToolbarItem {
        let label = mode == .source ? "Show rendered" : "Show source"
        let symbol = mode == .source ? "eye" : "doc.plaintext"
        return .custom(
            id: "marginaliaModeToggle",
            label: label,
            systemImage: symbol,
            shortcut: nil,
            topLevel: true,
            action: {
                let next: MarginaliaMode = (mode == .source) ? .wysiwyg : .source
                modeRawValue = next.rawValue
            }
        )
    }

    @ViewBuilder
    private var editorBody: some View {
        if let controller = hosting.controller {
            #if os(macOS)
            MarginaliaTextViewMac(
                controller: controller,
                text: $text,
                selection: $selection,
                sizing: configuration.sizing,
                minHeight: configuration.minHeight,
                contextMenuItems: macContextMenuItems()
            )
            .modifier(SizingFrame(sizing: configuration.sizing))
            #else
            MarginaliaTextViewIOS(
                controller: controller,
                text: $text,
                selection: $selection,
                sizing: configuration.sizing,
                minHeight: configuration.minHeight,
                editMenuBuilder: makeIOSEditMenuBuilder(controller: controller)
            )
            .modifier(SizingFrame(sizing: configuration.sizing))
            #endif
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: configuration.minHeight)
        }
    }

    #if os(macOS)
    private func macContextMenuItems() -> [MarginaliaContextMenuItem] {
        var items: [MarginaliaContextMenuItem] = []
        if !configuration.toolbar.isEmpty {
            let visible = toolbarVisible
            items.append(MarginaliaContextMenuItem(
                title: "Show Toolbar",
                systemImage: "richtext.page",
                isOn: visible,
                action: { toolbarVisible.toggle() }
            ))
        }
        items.append(contentsOf: configuration.contextMenuItems.map { item in
            MarginaliaContextMenuItem(
                title: item.title,
                systemImage: item.systemImage,
                isOn: item.isOn,
                action: item.action
            )
        })
        return items
    }
    #endif

    #if os(iOS)
    private func makeIOSEditMenuBuilder(controller: EditorController) -> MarginaliaTextViewIOS.EditMenuBuilder? {
        let toolbar = configuration.toolbar
        guard !toolbar.isEmpty else { return nil }
        let textBinding = $text
        return { _, suggested in
            var topLevel: [UIAction] = []
            var sections: [UIMenuElement] = []
            var current: [UIAction] = []
            func flush() {
                if !current.isEmpty {
                    sections.append(UIMenu(title: "", options: .displayInline, children: current))
                    current.removeAll()
                }
            }
            for item in toolbar {
                switch item {
                case .action(let action):
                    current.append(UIAction(
                        title: editMenuTitle(for: action),
                        image: UIImage(systemName: editMenuSymbol(for: action))
                    ) { _ in
                        MarginaliaToolbarActions.perform(
                            action,
                            controller: controller,
                            text: textBinding
                        )
                    })
                case .custom(_, let label, let symbol, _, let isTopLevel, let custom):
                    let action = UIAction(
                        title: label,
                        image: UIImage(systemName: symbol),
                        handler: { _ in custom() }
                    )
                    if isTopLevel {
                        flush()
                        topLevel.append(action)
                    } else {
                        current.append(action)
                    }
                case .divider, .spacer:
                    flush()
                }
            }
            flush()
            var children: [UIMenuElement] = suggested
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
    }
    #endif
}

#if os(iOS)
private func editMenuTitle(for action: Marginalia.Action) -> String {
    switch action {
    case .bold: return "Bold"
    case .italic: return "Italic"
    case .strikethrough: return "Strikethrough"
    case .heading(let level): return "Heading \(level)"
    case .unorderedList: return "Bullet List"
    case .orderedList: return "Numbered List"
    case .taskList: return "Task List"
    case .blockquote: return "Quote"
    case .codeSpan: return "Inline Code"
    case .codeBlock: return "Code Block"
    case .link: return "Link"
    case .horizontalRule: return "Horizontal Rule"
    }
}

private func editMenuSymbol(for action: Marginalia.Action) -> String {
    switch action {
    case .bold: return "bold"
    case .italic: return "italic"
    case .strikethrough: return "strikethrough"
    case .heading(let level): return "h\(level).square"
    case .unorderedList: return "list.bullet"
    case .orderedList: return "list.number"
    case .taskList: return "checklist"
    case .blockquote: return "text.quote"
    case .codeSpan: return "chevron.left.slash.chevron.right"
    case .codeBlock: return "curlybraces"
    case .link: return "link"
    case .horizontalRule: return "minus"
    }
}
#endif

/// In `.fitsContent` mode the representable reports its content height via
/// `intrinsicContentSize`/`sizeThatFits`, so the SwiftUI frame must NOT be
/// `maxHeight: .infinity` (that would override the intrinsic height). In
/// `.fillContainer` mode we want it to fill.
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

/// Holder around the `EditorController` so SwiftUI's `@StateObject` lifecycle
/// keeps it alive across body re-evaluations. `controller` is `@Published`
/// so the body re-renders past the initial `ProgressView` once the
/// controller finishes setting up.
final class MarginaliaHosting: ObservableObject {
    @Published var controller: EditorController?

    func ensureController(
        initialText: String,
        dialect: Highlighter.Dialect,
        theme: MarginaliaTheme,
        mode: MarginaliaMode
    ) {
        if controller == nil {
            let c = try? EditorController(initialText: initialText, theme: theme, dialect: dialect)
            c?.mode = mode
            controller = c
        }
    }
}
