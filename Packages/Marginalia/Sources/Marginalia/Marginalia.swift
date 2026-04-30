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
///     .marginaliaDialect(.commonMark)
///     .marginaliaInlineContentProvider { content in
///         MarginaliaChip.attachment(for: content)
///     }
///     .marginaliaPreviewRenderer { source, dialect in
///         AttributedString(source)
///     }
///     .frame(minHeight: 240)
/// ```
///
/// `Marginalia` is intentionally a **value** view: bindings come in via
/// `init`, configuration comes in via the `.marginalia*` modifiers (which
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
    @Environment(\.marginaliaPreviewRenderer) private var previewRenderer

    @State private var showPreview = false
    @StateObject private var hosting = MarginaliaHosting()

    public init(text: Binding<String>, selection: Binding<NSRange> = .constant(NSRange(location: 0, length: 0))) {
        self._text = text
        self._selection = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !configuration.toolbar.isEmpty || !configuration.statusItems.isEmpty {
                HStack(spacing: 12) {
                    if !configuration.toolbar.isEmpty {
                        MarginaliaToolbar(
                            items: configuration.toolbar,
                            showPreview: $showPreview,
                            canPreview: previewRenderer != nil,
                            perform: { action in
                                guard let controller = hosting.controller else { return }
                                MarginaliaToolbarActions.perform(
                                    action,
                                    controller: controller,
                                    text: $text,
                                    showPreview: $showPreview
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
            }
            if showPreview, let renderer = previewRenderer {
                MarginaliaPreview(source: text, dialect: dialect, renderer: renderer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorBody
            }
        }
        .onAppear {
            hosting.ensureController(initialText: text, dialect: dialect, theme: theme)
            if let controller = hosting.controller, controller.text != text {
                controller.setText(text)
            }
        }
        .onChange(of: dialect) { _, newDialect in
            hosting.controller?.dialect = newDialect
        }
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
                minHeight: configuration.minHeight
            )
            .modifier(SizingFrame(sizing: configuration.sizing))
            #else
            MarginaliaTextViewIOS(
                controller: controller,
                text: $text,
                selection: $selection,
                sizing: configuration.sizing,
                minHeight: configuration.minHeight
            )
            .modifier(SizingFrame(sizing: configuration.sizing))
            #endif
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: configuration.minHeight)
        }
    }
}

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

    func ensureController(initialText: String, dialect: Highlighter.Dialect, theme: MarginaliaTheme) {
        if controller == nil {
            controller = try? EditorController(initialText: initialText, theme: theme, dialect: dialect)
        }
    }
}
