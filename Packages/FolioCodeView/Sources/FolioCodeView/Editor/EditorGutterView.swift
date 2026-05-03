import SwiftUI
import FolioHighlight
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct EditorGutterView: View {
    let layoutManager: NSTextLayoutManager?
    let startLine: Int
    let theme: HighlightTheme
    let font: PlatformFont
    let editVersion: Int

    var body: some View {
        #if os(macOS)
        MacGutter(
            layoutManager: layoutManager,
            startLine: startLine,
            theme: theme,
            font: font,
            editVersion: editVersion
        )
        #elseif canImport(UIKit)
        IOSGutter(
            layoutManager: layoutManager,
            startLine: startLine,
            theme: theme,
            font: font,
            editVersion: editVersion
        )
        #else
        EmptyView()
        #endif
    }
}

#if os(macOS)

private struct MacGutter: NSViewRepresentable {
    let layoutManager: NSTextLayoutManager?
    let startLine: Int
    let theme: HighlightTheme
    let font: PlatformFont
    let editVersion: Int

    func makeNSView(context: Context) -> GutterNSView {
        let view = GutterNSView()
        view.theme = theme
        view.startLine = startLine
        view.gutterFont = font
        view.layoutManager = layoutManager
        return view
    }

    func updateNSView(_ nsView: GutterNSView, context: Context) {
        nsView.theme = theme
        nsView.startLine = startLine
        nsView.gutterFont = font
        nsView.layoutManager = layoutManager
        nsView.needsDisplay = true
    }
}

final class GutterNSView: NSView {
    var theme: HighlightTheme = .light { didSet { needsDisplay = true } }
    var startLine: Int = 1 { didSet { needsDisplay = true } }
    var gutterFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    var layoutManager: NSTextLayoutManager? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        theme.contextGutter.setFill()
        bounds.fill()

        guard let layoutManager else { return }
        guard let documentRange = layoutManager.textContentManager?.documentRange else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: theme.lineNumber
        ]

        var lineIndex = 0
        layoutManager.enumerateTextLayoutFragments(
            from: documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            for line in fragment.textLineFragments {
                let lineNumberString = "\(startLine + lineIndex)" as NSString
                let textSize = lineNumberString.size(withAttributes: attrs)
                let lineFrame = line.typographicBounds.offsetBy(
                    dx: fragment.layoutFragmentFrame.origin.x,
                    dy: fragment.layoutFragmentFrame.origin.y
                )
                let drawX = bounds.maxX - textSize.width - 4
                let drawY = lineFrame.midY - textSize.height / 2
                lineNumberString.draw(at: CGPoint(x: drawX, y: drawY), withAttributes: attrs)
                lineIndex += 1
            }
            return true
        }
    }
}

#elseif canImport(UIKit)

private struct IOSGutter: UIViewRepresentable {
    let layoutManager: NSTextLayoutManager?
    let startLine: Int
    let theme: HighlightTheme
    let font: PlatformFont
    let editVersion: Int

    func makeUIView(context: Context) -> GutterUIView {
        let view = GutterUIView()
        view.theme = theme
        view.startLine = startLine
        view.gutterFont = font
        view.layoutManager = layoutManager
        return view
    }

    func updateUIView(_ uiView: GutterUIView, context: Context) {
        uiView.theme = theme
        uiView.startLine = startLine
        uiView.gutterFont = font
        uiView.layoutManager = layoutManager
        uiView.setNeedsDisplay()
    }
}

final class GutterUIView: UIView {
    var theme: HighlightTheme = .light { didSet { setNeedsDisplay() } }
    var startLine: Int = 1 { didSet { setNeedsDisplay() } }
    var gutterFont: UIFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    var layoutManager: NSTextLayoutManager? { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(theme.contextGutter.cgColor)
        context.fill(bounds)

        guard let layoutManager else { return }
        guard let documentRange = layoutManager.textContentManager?.documentRange else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: theme.lineNumber
        ]

        var lineIndex = 0
        layoutManager.enumerateTextLayoutFragments(
            from: documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            for line in fragment.textLineFragments {
                let lineNumberString = "\(startLine + lineIndex)" as NSString
                let textSize = lineNumberString.size(withAttributes: attrs)
                let lineFrame = line.typographicBounds.offsetBy(
                    dx: fragment.layoutFragmentFrame.origin.x,
                    dy: fragment.layoutFragmentFrame.origin.y
                )
                let drawX = bounds.maxX - textSize.width - 4
                let drawY = lineFrame.midY - textSize.height / 2
                lineNumberString.draw(at: CGPoint(x: drawX, y: drawY), withAttributes: attrs)
                lineIndex += 1
            }
            return true
        }
    }
}
#endif
