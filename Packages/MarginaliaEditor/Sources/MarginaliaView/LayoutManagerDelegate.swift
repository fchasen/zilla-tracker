import Foundation
import MarginaliaSyntax
import MarginaliaRendering
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Picks an `NSTextLayoutFragment` subclass per paragraph based on the block
/// classifier's most recent output. The controller refreshes
/// `blockRegions` after every parse, and the delegate looks up which kind
/// of block the requested element falls inside.
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
              let placement = blockPlacement(for: textElement, in: controller) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        switch placement.region.kind {
        case .blockquote:
            return BlockquoteLayoutFragment(textElement: textElement, range: textElement.elementRange)
        case .horizontalRule:
            return HorizontalRuleLayoutFragment(textElement: textElement, range: textElement.elementRange)
        case .fencedCode(let language):
            let fragment = FencedCodeBlockLayoutFragment(
                textElement: textElement,
                range: textElement.elementRange
            )
            fragment.language = language
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

    private struct BlockPlacement {
        let region: BlockRegion
        let isFirstLine: Bool
        let isLastLine: Bool
    }

    private func blockPlacement(for element: NSTextElement, in controller: EditorController) -> BlockPlacement? {
        guard let elementRange = element.elementRange else { return nil }
        let storage = controller.contentStorage
        let elementDisplayStart = storage.offset(from: storage.documentRange.location, to: elementRange.location)
        let elementDisplayEnd = storage.offset(from: storage.documentRange.location, to: elementRange.endLocation)
        // Element ranges live in display coordinates; BlockRegions live in
        // source coordinates. Bridge through the controller's mapping so
        // dispatch + first/last math work in both modes.
        let mapping = controller.displayMapping
        let elementSourceStart = mapping.sourcePosition(forDisplay: elementDisplayStart)
        for region in controller.blockRegions {
            if region.range.contains(elementSourceStart) {
                let blockDisplayRange = mapping.displayRange(forSource: region.range)
                let blockDisplayEnd = blockDisplayRange.location + blockDisplayRange.length
                let isFirstLine = elementDisplayStart == blockDisplayRange.location
                // The element range may or may not include a trailing newline
                // that's also the block's terminator — count "ends within one
                // of the block's last display char" as the closing line.
                let isLastLine = elementDisplayEnd >= blockDisplayEnd - 1
                return BlockPlacement(region: region, isFirstLine: isFirstLine, isLastLine: isLastLine)
            }
        }
        return nil
    }
}
