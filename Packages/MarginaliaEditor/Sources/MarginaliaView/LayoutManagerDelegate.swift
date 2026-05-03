import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public final class LayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    public weak var controller: EditorController?

    public init(controller: EditorController? = nil) {
        self.controller = controller
        super.init()
    }

    public func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        guard let controller,
              let placement = placement(for: textElement, in: controller) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        let block = placement.attribute
        if block.blockquoteDepth > 0 {
            return BlockquoteLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        switch block.tag {
        case .horizontalRule:
            return HorizontalRuleLayoutFragment(textElement: textElement, range: textElement.elementRange)
        case .fencedCode:
            let fragment = FencedCodeBlockLayoutFragment(
                textElement: textElement,
                range: textElement.elementRange
            )
            fragment.language = block.language
            fragment.isFirstLine = placement.isFirstLine
            fragment.isLastLine = placement.isLastLine
            return fragment
        case .indentedCode:
            let fragment = IndentedCodeBlockLayoutFragment(
                textElement: textElement,
                range: textElement.elementRange
            )
            fragment.isFirstLine = placement.isFirstLine
            fragment.isLastLine = placement.isLastLine
            return fragment
        case .pipeTable:
            let fragment = PipeTableLayoutFragment(
                textElement: textElement,
                range: textElement.elementRange
            )
            fragment.isFirstLine = placement.isFirstLine
            fragment.isLastLine = placement.isLastLine
            return fragment
        default:
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
    }

    private struct Placement {
        let attribute: BlockAttribute
        let isFirstLine: Bool
        let isLastLine: Bool
    }

    private func placement(for element: NSTextElement, in controller: EditorController) -> Placement? {
        guard let elementRange = element.elementRange else { return nil }
        let storage = controller.contentStorage
        let elementStart = storage.offset(from: storage.documentRange.location, to: elementRange.location)
        let elementEnd = storage.offset(from: storage.documentRange.location, to: elementRange.endLocation)
        let total = controller.textStorage.length
        guard elementStart >= 0, elementStart < total else { return nil }
        var attrRange = NSRange(location: 0, length: 0)
        let raw = controller.textStorage.attribute(
            .marginaliaBlock,
            at: elementStart,
            longestEffectiveRange: &attrRange,
            in: NSRange(location: 0, length: total)
        )
        guard let block = raw as? BlockAttribute else { return nil }
        let isFirst = elementStart == attrRange.location
        let isLast = elementEnd >= attrRange.location + attrRange.length - 1
        return Placement(attribute: block, isFirstLine: isFirst, isLastLine: isLast)
    }
}
