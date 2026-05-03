import SwiftUI
import FolioHighlight
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct CodeBlockView: View {
    @Binding var text: String
    let language: CodeLanguage
    let startLine: Int
    let theme: HighlightTheme
    let showsLineNumbers: Bool

    @Environment(\.folioFontScale) private var folioFontScale
    @State private var layoutManager: NSTextLayoutManager?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if showsLineNumbers {
                EditorGutterView(
                    layoutManager: layoutManager,
                    startLine: startLine,
                    theme: theme,
                    font: editorFont,
                    editVersion: text.hashValue
                )
                .frame(width: gutterWidth + 8)
            }
            CodeEditorRepresentable(
                text: $text,
                language: language,
                theme: theme,
                font: editorFont,
                onLayoutManagerReady: { manager in
                    Task { @MainActor in
                        if layoutManager !== manager {
                            layoutManager = manager
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)
        }
        .background(Color(theme.contextRow))
    }

    private var lineCount: Int {
        max(1, text.components(separatedBy: "\n").count)
    }

    private var gutterWidth: CGFloat {
        let last = startLine + max(0, lineCount - 1)
        let widest = max(String(last).count, 3)
        return CGFloat(widest) * 7 + 4
    }

    private var editorFont: PlatformFont {
        let baseSize = Font.TextStyle.caption.folioBaseSize * folioFontScale
        return .monospacedSystemFont(ofSize: baseSize, weight: .regular)
    }
}
