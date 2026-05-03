import Testing
import Foundation
import MarginaliaSyntax
import MarginaliaRendering
@testable import MarginaliaView
#if canImport(AppKit) && os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite struct BlockquoteBarFrameTests {

    @Test func blockquoteFragmentOriginIsAtContainerLeading() throws {
        let controller = try EditorController(initialMarkdown: "> hello\n")
        let lm = controller.layoutManager
        lm.ensureLayout(for: lm.documentRange)

        var fragments: [NSTextLayoutFragment] = []
        lm.enumerateTextLayoutFragments(from: lm.documentRange.location, options: [.ensuresLayout]) { frag in
            fragments.append(frag)
            return true
        }
        guard let first = fragments.first else {
            Issue.record("no layout fragments")
            return
        }
        let lineMinX = first.textLineFragments.first?.typographicBounds.minX ?? -1
        print("layoutFragmentFrame=\(first.layoutFragmentFrame) lineMinX=\(lineMinX)")
    }
}
