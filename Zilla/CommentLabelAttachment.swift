import MarkdownEditorKit
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The editor-side twin of `ZillaCommentLabelTarget`: a bare SF Symbol sized to
/// the line, no capsule and no text, so the composer shows the same glyph the
/// rendered comment does.
final class CommentLabelAttachment: NSTextAttachment, MarkdownSourceAttachment {
    var systemImage: String = PhabricatorIcons.fallbackSystemImage
    var name: String = ""
    var markdownSource: String = ""
    var contentKind: String = CommentLabels.inlineContentKind

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let side = Self.pointSize(for: lineFrag.height)
        return CGRect(x: 0, y: -1, width: ceil(side * 1.15), height: side)
    }

    /// TextKit calls this on the main thread, which is the point: the provider
    /// that builds the attachment also runs on the compile queue, where
    /// rendering an image is not safe.
    override func image(
        forBounds imageBounds: CGRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> PlatformImage? {
        Self.symbolImage(systemImage, size: imageBounds.size)
    }

    private static func pointSize(for lineHeight: CGFloat) -> CGFloat {
        max(11, min(lineHeight - 3, 20))
    }

    private static func symbolImage(_ name: String, size: CGSize) -> PlatformImage? {
        let configuration = PlatformImage.SymbolConfiguration(
            pointSize: max(1, size.height),
            weight: .semibold
        )
        #if canImport(AppKit) && os(macOS)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: PhabricatorIcons.fallbackSystemImage, accessibilityDescription: nil)
        else { return nil }
        let symbol = base.withSymbolConfiguration(configuration) ?? base
        let tinted = NSImage(size: size, flipped: false) { rect in
            NSColor.secondaryLabelColor.set()
            let fitted = Self.aspectFit(symbol.size, in: rect)
            symbol.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1)
            rect.fill(using: .sourceAtop)
            return true
        }
        return tinted
        #elseif canImport(UIKit)
        let base = UIImage(systemName: name, withConfiguration: configuration)
            ?? UIImage(systemName: PhabricatorIcons.fallbackSystemImage, withConfiguration: configuration)
        return base?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
        #else
        return nil
        #endif
    }

    #if canImport(AppKit) && os(macOS)
    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
    #endif
}
