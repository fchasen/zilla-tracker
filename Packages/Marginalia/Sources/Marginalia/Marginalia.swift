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
            if !configuration.toolbar.isEmpty {
                MarginaliaToolbar(
                    items: configuration.toolbar,
                    showPreview: $showPreview,
                    text: $text,
                    selection: $selection,
                    canPreview: previewRenderer != nil
                )
                .disabled(showPreview)
            }
            if showPreview, let renderer = previewRenderer {
                MarginaliaPreview(source: text, dialect: dialect, renderer: renderer)
            } else {
                editorBody
            }
            if !configuration.statusItems.isEmpty {
                MarginaliaStatusBar(
                    items: configuration.statusItems,
                    text: text,
                    selection: selection
                )
            }
        }
        .onAppear {
            hosting.ensureController(initialText: text, dialect: dialect, theme: theme)
            hosting.controller?.setText(text)
        }
        .onChange(of: dialect) { _, newDialect in
            hosting.controller?.dialect = newDialect
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        if let controller = hosting.controller {
            #if os(macOS)
            MarginaliaTextViewMac(controller: controller, text: $text, selection: $selection)
            #else
            MarginaliaTextViewIOS(controller: controller, text: $text, selection: $selection)
            #endif
        } else {
            ProgressView()
        }
    }
}

/// Holder around the `EditorController` so SwiftUI's `@StateObject` lifecycle
/// keeps it alive across body re-evaluations.
final class MarginaliaHosting: ObservableObject {
    var controller: EditorController?

    func ensureController(initialText: String, dialect: Highlighter.Dialect, theme: MarginaliaTheme) {
        if controller == nil {
            controller = try? EditorController(initialText: initialText, theme: theme, dialect: dialect)
        }
    }
}
