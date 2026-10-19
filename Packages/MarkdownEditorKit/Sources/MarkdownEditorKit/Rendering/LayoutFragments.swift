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

public struct QuoteBar: Equatable {
    public var offset: CGFloat
    public var isFirstInRun: Bool
    public var isLastInRun: Bool
}

public class MarkdownLayoutFragment: NSTextLayoutFragment {
    public var barWidth: CGFloat = 3
    public var barInset: CGFloat = 1
    weak var controller: MarkdownEditorController?
    var fixedDecorations = FragmentDecorations()

    var decorations: FragmentDecorations {
        guard let controller,
              let elementStart = textElement?.elementRange?.location else { return fixedDecorations }
        let storage = controller.textContentStorage
        let offset = storage.offset(from: storage.documentRange.location, to: elementStart)
        return FragmentDecorations.make(paragraphAt: offset, controller: controller)
    }

    public var marker: ListMarker? { decorations.marker }
    public var quoteBars: [QuoteBar] { decorations.quoteBars }
    public var barColor: PlatformColor { decorations.barColor }

    var contentStartX: CGFloat {
        guard let line = textLineFragments.first else { return 0 }
        return line.typographicBounds.minX + line.locationForCharacter(at: 0).x
    }

    var lineFragmentPadding: CGFloat {
        textLayoutManager?.textContainer?.lineFragmentPadding ?? 5
    }

    var firstBaseline: CGFloat? {
        guard let line = textLineFragments.first else { return nil }
        return line.typographicBounds.minY + line.glyphOrigin.y
    }

    func markerAnchorX(_ decorations: FragmentDecorations) -> CGFloat {
        contentStartX - (decorations.leadingIndent - decorations.markerIndent)
    }

    var markerRect: CGRect? {
        let decorations = decorations
        guard let marker = decorations.marker, let baseline = firstBaseline else { return nil }
        let anchor = markerAnchorX(decorations)
        switch marker.kind {
        case .task:
            return ListMarkerRenderer.taskBoxRect(font: marker.font, anchorX: anchor, baseline: baseline)
        case .bullet, .ordinal:
            let height = marker.font.ascender - marker.font.descender
            let width = Restyler.listIndent - ListMarkerRenderer.gap
            return CGRect(x: anchor - Restyler.listIndent, y: baseline - marker.font.ascender, width: width, height: height)
        }
    }

    public override func draw(at point: CGPoint, in context: CGContext) {
        drawDecorations(decorations, at: point, in: context)
        super.draw(at: point, in: context)
    }

    func drawDecorations(_ decorations: FragmentDecorations, at point: CGPoint, in context: CGContext) {
        guard decorations.isDecorated else { return }
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        if !decorations.quoteBars.isEmpty {
            let bounds = layoutFragmentFrame
            let lines = textLineFragments
            let origin = contentStartX - decorations.leadingIndent - lineFragmentPadding
            context.setFillColor(decorations.barColor.cgColor)
            for bar in decorations.quoteBars {
                let topY = bar.isFirstInRun ? (lines.first?.typographicBounds.minY ?? 0) : 0
                let bottomY = bar.isLastInRun ? (lines.last?.typographicBounds.maxY ?? bounds.height) : bounds.height
                let rect = CGRect(x: origin + bar.offset + barInset, y: topY, width: barWidth, height: max(0, bottomY - topY))
                context.fill(rect)
            }
        }
        if let marker = decorations.marker, let baseline = firstBaseline {
            ListMarkerRenderer.draw(marker, anchorX: markerAnchorX(decorations), baseline: baseline, in: context)
        }
        context.restoreGState()
    }

    public override var renderingSurfaceBounds: CGRect {
        let typographic = super.renderingSurfaceBounds
        guard fixedDecorations.isDecorated || controller != nil else { return typographic }
        let minX = min(typographic.minX, -layoutFragmentFrame.origin.x)
        return CGRect(x: minX, y: typographic.minY, width: typographic.maxX - minX, height: typographic.height)
    }
}

public class CodeBlockLayoutFragment: MarkdownLayoutFragment {
    public var horizontalInset: CGFloat = 0
    public var horizontalPadding: CGFloat = 8
    public var containerWidth: CGFloat = 0
    public var trailingInset: CGFloat = 0
    public var verticalPadding: CGFloat = 4
    public var isFirstLine: Bool = false
    public var isLastLine: Bool = false
    public var fillColor: PlatformColor = .codeBlockDefaultFill

    fileprivate func effectiveWidth(bounds: CGRect) -> CGFloat {
        if let live = textLayoutManager?.textContainer?.size.width, live > 0 {
            return live
        }
        if containerWidth > 0 { return containerWidth }
        return bounds.width
    }
}

public final class FencedCodeBlockLayoutFragment: CodeBlockLayoutFragment {
    public var language: String?
    public var languageTagColor: PlatformColor = .codeBlockDefaultTag
    public var languageTagInset: CGFloat = 6

    public override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard isFirstLine, let language, !language.isEmpty else { return }
        let bounds = layoutFragmentFrame
        let width = effectiveWidth(bounds: bounds)
        let firstLine = textLineFragments.first?.typographicBounds
        let lineMinY = firstLine?.minY ?? 0
        let lineMaxY = firstLine?.maxY ?? bounds.height
        let rect = CGRect(
            x: horizontalInset - bounds.origin.x,
            y: lineMinY,
            width: max(0, width - 2 * horizontalInset - trailingInset),
            height: lineMaxY - lineMinY
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: codeBlockTagFont(),
            .foregroundColor: controller?.theme.codeBlock.languageTagColor ?? languageTagColor
        ]
        let string = language as NSString
        let size = string.size(withAttributes: attrs)
        let origin = CGPoint(
            x: rect.maxX - size.width - languageTagInset,
            y: rect.minY + (rect.height - size.height) / 2
        )
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        #if canImport(AppKit) && os(macOS)
        let nsContext = NSGraphicsContext(cgContext: context, flipped: layoutFragmentFrame.height > 0)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        string.draw(at: origin, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        #else
        string.draw(at: origin, withAttributes: attrs)
        #endif
        context.restoreGState()
    }
}


private func codeBlockTagFont() -> PlatformFont {
    #if canImport(AppKit) && os(macOS)
    return NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    #else
    return UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    #endif
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

    public static var codeBlockDefaultFill: PlatformColor {
        #if canImport(AppKit) && os(macOS)
        return NSColor.tertiaryLabelColor.withAlphaComponent(0.08)
        #else
        return UIColor.tertiaryLabel.withAlphaComponent(0.08)
        #endif
    }

    static var codeBlockDefaultTag: PlatformColor {
        #if canImport(AppKit) && os(macOS)
        return NSColor.secondaryLabelColor
        #else
        return UIColor.secondaryLabel
        #endif
    }
}
