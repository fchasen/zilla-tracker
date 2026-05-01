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
        guard let controller else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        guard let kind = blockKind(for: textElement, in: controller) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        switch kind {
        case .fencedCode, .indentedCode:
            return CodeBlockLayoutFragment(textElement: textElement, range: textElement.elementRange)
        case .blockquote:
            return BlockquoteLayoutFragment(textElement: textElement, range: textElement.elementRange)
        case .horizontalRule:
            return HorizontalRuleLayoutFragment(textElement: textElement, range: textElement.elementRange)
        default:
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
    }

    private func blockKind(for element: NSTextElement, in controller: EditorController) -> BlockKind? {
        guard let elementRange = element.elementRange else { return nil }
        let lowerLocation = elementRange.location
        let storage = controller.contentStorage
        let docOffset = storage.offset(from: storage.documentRange.location, to: lowerLocation)
        for region in controller.blockRegions {
            if region.range.contains(docOffset) {
                return region.kind
            }
        }
        return nil
    }
}
