import CoreGraphics
import Testing
@testable import Zilla

struct CompletionPopupPlacementTests {
    @Test func placesBelowWhenThereIsRoom() {
        let anchor = CGRect(x: 40, y: 40, width: 2, height: 20)
        let origin = CompletionPopupPlacement.origin(
            anchorRect: anchor,
            menuSize: CGSize(width: 180, height: 120),
            containerBounds: CGRect(x: 0, y: 0, width: 320, height: 400)
        )

        #expect(origin.y >= anchor.maxY)
    }

    @Test func placesAboveWhenViewportBottomIsClose() {
        let anchor = CGRect(x: 40, y: 40, width: 2, height: 20)
        let menuSize = CGSize(width: 180, height: 120)
        let origin = CompletionPopupPlacement.origin(
            anchorRect: anchor,
            menuSize: menuSize,
            containerBounds: CGRect(x: 0, y: -260, width: 320, height: 340)
        )

        #expect(origin.y + menuSize.height <= anchor.minY)
    }

    @Test func edgeInsetFlipsBeforeMenuBarelyFitsBelow() {
        let anchor = CGRect(x: 40, y: 200, width: 2, height: 20)
        let menuSize = CGSize(width: 180, height: 160)
        let origin = CompletionPopupPlacement.origin(
            anchorRect: anchor,
            menuSize: menuSize,
            containerBounds: CGRect(x: 0, y: 0, width: 320, height: 388)
        )

        #expect(origin.y + menuSize.height <= anchor.minY)
    }

    @Test func placesAboveWhenBelowWouldCoverOrOverflow() {
        let anchor = CGRect(x: 40, y: 340, width: 2, height: 20)
        let menuSize = CGSize(width: 180, height: 120)
        let origin = CompletionPopupPlacement.origin(
            anchorRect: anchor,
            menuSize: menuSize,
            containerBounds: CGRect(x: 0, y: 0, width: 320, height: 400)
        )

        #expect(origin.y + menuSize.height <= anchor.minY)
    }

    @Test func preservesLineGapWhenNeitherSideFits() {
        let anchor = CGRect(x: 40, y: 90, width: 2, height: 20)
        let menuSize = CGSize(width: 180, height: 200)
        let origin = CompletionPopupPlacement.origin(
            anchorRect: anchor,
            menuSize: menuSize,
            containerBounds: CGRect(x: 0, y: 0, width: 320, height: 150)
        )

        #expect(origin.y + menuSize.height <= anchor.minY || origin.y >= anchor.maxY)
    }
}
