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

        let spec = placement.spec
        if spec.blockquoteDepth > 0 {
            let fragment = BlockquoteLayoutFragment(textElement: textElement, range: textElement.elementRange)
            fragment.isFirstInRun = placement.isFirstInBlockquoteRun
            fragment.isLastInRun = placement.isLastInBlockquoteRun
            return fragment
        }
        switch spec.kind {
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

    private struct Placement {
        let spec: BlockSpec
        let isFirstLine: Bool
        let isLastLine: Bool
        let isFirstInBlockquoteRun: Bool
        let isLastInBlockquoteRun: Bool
    }

    private func placement(for element: NSTextElement, in controller: EditorController) -> Placement? {
        guard let elementRange = element.elementRange else { return nil }
        let storage = controller.contentStorage
        let elementStart = storage.offset(from: storage.documentRange.location, to: elementRange.location)
        let elementEnd = storage.offset(from: storage.documentRange.location, to: elementRange.endLocation)
        let total = controller.textStorage.length
        guard total > 0,
              elementStart >= 0,
              elementStart < total,
              elementEnd >= elementStart,
              elementEnd <= total else {
            return nil
        }
        // Probe the paragraph for any character carrying a BlockSpec — typing
        // can race with layout and leave individual characters spec-less while
        // the rest of the line is correct.
        guard let spec = paragraphSpec(in: controller.textStorage,
                                       from: elementStart,
                                       to: elementEnd) else {
            return nil
        }
        var attrRange = NSRange(location: elementStart, length: elementEnd - elementStart)
        controller.textStorage.enumerateAttribute(.marginaliaBlockSpec, in: attrRange) { value, range, _ in
            if value is BlockSpecBox { attrRange = range }
        }
        let isFirst = elementStart == attrRange.location
        let isLast = elementEnd >= attrRange.location + attrRange.length - 1

        var isFirstInBlockquote = true
        var isLastInBlockquote = true
        if spec.blockquoteDepth > 0 {
            if elementStart > 0,
               let prev = controller.textStorage.blockSpec(at: elementStart - 1),
               prev.blockquoteDepth > 0 {
                isFirstInBlockquote = false
            }
            if elementEnd < total,
               let next = controller.textStorage.blockSpec(at: elementEnd),
               next.blockquoteDepth > 0 {
                isLastInBlockquote = false
            }
        }

        return Placement(
            spec: spec,
            isFirstLine: isFirst,
            isLastLine: isLast,
            isFirstInBlockquoteRun: isFirstInBlockquote,
            isLastInBlockquoteRun: isLastInBlockquote
        )
    }

    private func paragraphSpec(in storage: NSAttributedString, from lo: Int, to hi: Int) -> BlockSpec? {
        var i = lo
        while i < hi {
            if let spec = storage.blockSpec(at: i) { return spec }
            i += 1
        }
        return nil
    }
}
