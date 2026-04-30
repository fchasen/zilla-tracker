import Foundation
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Visual styling — the editor surface's only "design system" knob.
///
/// Defaults match the rest of the Zilla UI: system body font for prose,
/// monospaced system for fenced/code spans, secondary label for dimmed
/// markup, link color for URLs.
public struct MarginaliaTheme {
    public var bodyFont: PlatformFont
    public var monospaceFont: PlatformFont
    public var foregroundColor: PlatformColor
    public var markupColor: PlatformColor
    public var linkColor: PlatformColor
    public var codeBackground: PlatformColor
    public var blockquoteBarColor: PlatformColor
    public var headingScale: [Int: CGFloat]

    public init(
        bodyFont: PlatformFont,
        monospaceFont: PlatformFont,
        foregroundColor: PlatformColor,
        markupColor: PlatformColor,
        linkColor: PlatformColor,
        codeBackground: PlatformColor,
        blockquoteBarColor: PlatformColor,
        headingScale: [Int: CGFloat] = [1: 1.6, 2: 1.4, 3: 1.25, 4: 1.15, 5: 1.05, 6: 1.0]
    ) {
        self.bodyFont = bodyFont
        self.monospaceFont = monospaceFont
        self.foregroundColor = foregroundColor
        self.markupColor = markupColor
        self.linkColor = linkColor
        self.codeBackground = codeBackground
        self.blockquoteBarColor = blockquoteBarColor
        self.headingScale = headingScale
    }

    public static var `default`: MarginaliaTheme {
        let body = PlatformFont.systemFont(ofSize: PlatformFont.systemFontSize)
        let mono = PlatformFont.monospacedSystemFont(ofSize: PlatformFont.systemFontSize, weight: .regular)
        #if canImport(AppKit) && os(macOS)
        return MarginaliaTheme(
            bodyFont: body,
            monospaceFont: mono,
            foregroundColor: .labelColor,
            markupColor: .tertiaryLabelColor,
            linkColor: .linkColor,
            codeBackground: NSColor.secondaryLabelColor.withAlphaComponent(0.08),
            blockquoteBarColor: NSColor.tertiaryLabelColor
        )
        #else
        return MarginaliaTheme(
            bodyFont: body,
            monospaceFont: mono,
            foregroundColor: .label,
            markupColor: .tertiaryLabel,
            linkColor: .link,
            codeBackground: UIColor.secondaryLabel.withAlphaComponent(0.08),
            blockquoteBarColor: .tertiaryLabel
        )
        #endif
    }
}
