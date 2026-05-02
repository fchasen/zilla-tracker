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

/// Paints a vertical sidebar bar on the left of every blockquote line.
public final class BlockquoteLayoutFragment: NSTextLayoutFragment {
    public var barColor: PlatformColor = .blockquoteDefaultBar
    public var barWidth: CGFloat = 3
    public var barInset: CGFloat = 1

    public override func draw(at point: CGPoint, in context: CGContext) {
        let lines = textLineFragments
        let barRect: CGRect
        if let first = lines.first, let last = lines.last {
            let topY = first.typographicBounds.minY
            let bottomY = last.typographicBounds.maxY
            barRect = CGRect(x: barInset, y: topY, width: barWidth, height: bottomY - topY)
        } else {
            let bounds = layoutFragmentFrame
            barRect = CGRect(x: barInset, y: 0, width: barWidth, height: bounds.height)
        }

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
