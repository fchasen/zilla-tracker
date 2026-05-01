#if canImport(AppKit) && os(macOS)
import AppKit
public typealias PlatformLayoutFragment = NSTextLayoutFragment
#elseif canImport(UIKit)
import UIKit
public typealias PlatformLayoutFragment = NSTextLayoutFragment
#else
import Foundation
public typealias PlatformLayoutFragment = NSTextLayoutFragment
#endif

import CoreGraphics
import MarginaliaSyntax

/// Custom `NSTextLayoutFragment` for fenced and indented code blocks. Paints
/// a subtle rounded background behind the block so the code reads as visually
/// distinct from prose.
public final class CodeBlockLayoutFragment: NSTextLayoutFragment {
    public var backgroundColor: PlatformColor = .codeBlockDefaultBackground
    public var cornerRadius: CGFloat = 4

    public override func draw(at point: CGPoint, in context: CGContext) {
        let bounds = layoutFragmentFrame
        let rect = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height
        ).insetBy(dx: -2, dy: -1)

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.setFillColor(backgroundColor.cgColor)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        super.draw(at: point, in: context)
    }
}

/// Paints a vertical sidebar bar on the left of every blockquote line.
public final class BlockquoteLayoutFragment: NSTextLayoutFragment {
    public var barColor: PlatformColor = .blockquoteDefaultBar
    public var barWidth: CGFloat = 3
    public var barInset: CGFloat = 1

    public override func draw(at point: CGPoint, in context: CGContext) {
        let bounds = layoutFragmentFrame
        let barRect = CGRect(
            x: barInset,
            y: 0,
            width: barWidth,
            height: bounds.height
        )

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.setFillColor(barColor.cgColor)
        context.fill(barRect)
        context.restoreGState()

        super.draw(at: point, in: context)
    }
}

/// Replaces the visible `---` / `***` of a thematic break with a thin
/// horizontal rule painted across the available width.
public final class HorizontalRuleLayoutFragment: NSTextLayoutFragment {
    public var ruleColor: PlatformColor = .horizontalRuleDefault
    public var ruleHeight: CGFloat = 1

    public override func draw(at point: CGPoint, in context: CGContext) {
        let bounds = layoutFragmentFrame
        let lineY = bounds.height / 2 - ruleHeight / 2
        let lineRect = CGRect(
            x: 0,
            y: lineY,
            width: bounds.width,
            height: ruleHeight
        )

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.setFillColor(ruleColor.cgColor)
        context.fill(lineRect)
        context.restoreGState()
        // Don't call super — we don't want the literal "---" text to draw.
    }
}

extension PlatformColor {
    static var codeBlockDefaultBackground: PlatformColor {
        #if canImport(AppKit) && os(macOS)
        return NSColor.secondaryLabelColor.withAlphaComponent(0.08)
        #else
        return UIColor.secondaryLabel.withAlphaComponent(0.08)
        #endif
    }

    static var blockquoteDefaultBar: PlatformColor {
        #if canImport(AppKit) && os(macOS)
        return NSColor.tertiaryLabelColor
        #else
        return UIColor.tertiaryLabel
        #endif
    }

    static var horizontalRuleDefault: PlatformColor {
        #if canImport(AppKit) && os(macOS)
        return NSColor.tertiaryLabelColor
        #else
        return UIColor.tertiaryLabel
        #endif
    }
}
