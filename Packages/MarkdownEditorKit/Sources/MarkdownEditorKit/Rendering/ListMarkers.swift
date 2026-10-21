import Foundation
import CoreGraphics
import CoreText
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct ListMarker: Equatable {
    public enum Kind: Equatable {
        case bullet(String)
        case ordinal(Int)
        case task(TaskState)
    }

    public var kind: Kind
    public var font: PlatformFont
    public var color: PlatformColor

    public var text: String? {
        switch kind {
        case .bullet(let glyph): return glyph
        case .ordinal(let number): return "\(number)."
        case .task: return nil
        }
    }
}

enum ListNumbering {
    static func itemNumber(at paragraphStart: Int, in storage: NSAttributedString) -> Int? {
        let lists = Normalizer.effectiveTextLists(in: storage, at: paragraphStart)
        guard let list = lists.last, list.hasOrderedMarker else { return nil }
        let depth = lists.count
        var count = 0
        var start = list.startingItemNumber
        var location = paragraphStart
        let ns = storage.string as NSString
        while location > 0 {
            let previous = ns.paragraphRange(for: NSRange(location: location - 1, length: 0))
            let previousLists = Normalizer.effectiveTextLists(in: storage, at: previous.location)
            guard previousLists.count >= depth, previousLists[depth - 1].hasOrderedMarker else { break }
            if previousLists.count == depth, storage.markdownBlock(at: previous.location)?.isContinuation != true {
                count += 1
                start = previousLists[depth - 1].startingItemNumber
            }
            location = previous.location
        }
        return start + count
    }

    static func markerKind(at paragraphStart: Int, in storage: NSAttributedString) -> ListMarker.Kind? {
        guard paragraphStart >= 0, paragraphStart < storage.length,
              let block = storage.markdownBlock(at: paragraphStart),
              !block.isContinuation else { return nil }
        let lists = Normalizer.effectiveTextLists(in: storage, at: paragraphStart)
        guard let list = lists.last else { return nil }
        if let task = block.task { return .task(task) }
        if list.hasOrderedMarker, let number = itemNumber(at: paragraphStart, in: storage) {
            return .ordinal(number)
        }
        return .bullet(bulletGlyph(for: list, depth: lists.count))
    }

    static func bulletGlyph(for list: NSTextList, depth: Int) -> String {
        let marker = list.marker(forItemNumber: 1)
        if !marker.isEmpty, marker.count <= 2 { return marker }
        let glyphs = ["•", "◦", "▪"]
        return glyphs[(max(1, depth) - 1) % glyphs.count]
    }

    static func listContentIndent(for block: MarkdownBlock) -> CGFloat {
        guard let last = block.containers.lastIndex(where: { if case .listItem = $0 { return true } else { return false } }) else {
            return 0
        }
        return block.containers[...last].reduce(CGFloat(0)) { total, container in
            switch container {
            case .quote: return total + Restyler.quoteIndent
            case .listItem: return total + Restyler.listIndent
            }
        }
    }

    static func leadingOffsets(ofQuotesIn block: MarkdownBlock) -> [CGFloat] {
        var offsets: [CGFloat] = []
        var total: CGFloat = 0
        for container in block.containers {
            switch container {
            case .quote:
                offsets.append(total)
                total += Restyler.quoteIndent
            case .listItem:
                total += Restyler.listIndent
            }
        }
        return offsets
    }
}

enum ListMarkerRenderer {
    static let gap: CGFloat = 6
    static let bulletCenterInset: CGFloat = 16
    static let taskBoxScale: CGFloat = 0.95

    static func draw(_ marker: ListMarker, anchorX: CGFloat, baseline: CGFloat, in context: CGContext) {
        switch marker.kind {
        case .bullet, .ordinal:
            guard let text = marker.text else { return }
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): marker.font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): marker.color.cgColor
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x: CGFloat
            if case .bullet = marker.kind {
                x = anchorX - bulletCenterInset - width / 2
            } else {
                x = anchorX - gap - width
            }
            context.saveGState()
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, context)
            context.restoreGState()
        case .task(let state):
            let rect = taskBoxRect(font: marker.font, anchorX: anchorX, baseline: baseline)
            context.saveGState()
            #if canImport(AppKit) && os(macOS)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            CheckboxAttachment.draw(checked: state.isChecked, in: rect)
            NSGraphicsContext.restoreGraphicsState()
            #else
            UIGraphicsPushContext(context)
            CheckboxAttachment.draw(checked: state.isChecked, in: rect)
            UIGraphicsPopContext()
            #endif
            context.restoreGState()
        }
    }

    static func taskBoxRect(font: PlatformFont, anchorX: CGFloat, baseline: CGFloat) -> CGRect {
        let side = max(10, (font.ascender - font.descender) * taskBoxScale)
        let centerY = baseline - font.capHeight / 2
        return CGRect(x: anchorX - gap - side, y: centerY - side / 2, width: side, height: side)
    }
}

enum MarkdownTaskGutter {
    static let width: CGFloat = 28
}
