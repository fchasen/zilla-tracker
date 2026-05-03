import Testing
import Foundation
@testable import MarginaliaSyntax

@Suite struct DisplayTransformTests {

    @Test func emptyElidesProduceIdentityMapping() {
        let mapping = DisplayTransform.transform(source: "hello", elideRanges: [])
        #expect(mapping.displayString == "hello")
        #expect(mapping.sourceLength == 5)
        #expect(mapping.runs.count == 1)
        #expect(mapping.runs.first?.kind == .verbatim)
    }

    @Test func singleElideStripsRange() {
        let source = "# Heading"
        let elide = NSRange(location: 0, length: 2)
        let mapping = DisplayTransform.transform(source: source, elideRanges: [elide])
        #expect(mapping.displayString == "Heading")
        #expect(mapping.sourceLength == 9)
    }

    @Test func multipleElidesStripAllRanges() {
        let source = "**bold**"
        let elides = [
            NSRange(location: 0, length: 2),
            NSRange(location: 6, length: 2)
        ]
        let mapping = DisplayTransform.transform(source: source, elideRanges: elides)
        #expect(mapping.displayString == "bold")
    }

    @Test func displayPositionMapsThroughVerbatimRun() {
        let mapping = DisplayTransform.transform(source: "hello", elideRanges: [])
        #expect(mapping.displayPosition(forSource: 0) == 0)
        #expect(mapping.displayPosition(forSource: 3) == 3)
        #expect(mapping.displayPosition(forSource: 5) == 5)
    }

    @Test func displayPositionCollapsesAcrossElide() {
        let mapping = DisplayTransform.transform(
            source: "# Heading",
            elideRanges: [NSRange(location: 0, length: 2)]
        )
        #expect(mapping.displayPosition(forSource: 0) == 0)
        #expect(mapping.displayPosition(forSource: 1) == 0)
        #expect(mapping.displayPosition(forSource: 2) == 0)
        #expect(mapping.displayPosition(forSource: 3) == 1)
        #expect(mapping.displayPosition(forSource: 9) == 7)
    }

    @Test func sourcePositionMapsThroughVerbatimRun() {
        let mapping = DisplayTransform.transform(source: "hello", elideRanges: [])
        #expect(mapping.sourcePosition(forDisplay: 0) == 0)
        #expect(mapping.sourcePosition(forDisplay: 3) == 3)
        #expect(mapping.sourcePosition(forDisplay: 5) == 5)
    }

    @Test func sourcePositionAdvancesPastElide() {
        let mapping = DisplayTransform.transform(
            source: "# Heading",
            elideRanges: [NSRange(location: 0, length: 2)]
        )
        #expect(mapping.sourcePosition(forDisplay: 0) == 2)
        #expect(mapping.sourcePosition(forDisplay: 1) == 3)
        #expect(mapping.sourcePosition(forDisplay: 7) == 9)
    }

    @Test func displayRangeForSourceRangeWithVerbatimAndElide() {
        let source = "# Title\nbody"
        let mapping = DisplayTransform.transform(
            source: source,
            elideRanges: [NSRange(location: 0, length: 2)]
        )
        #expect(mapping.displayString == "Title\nbody")
        let titleSource = (source as NSString).range(of: "Title")
        let titleDisplay = mapping.displayRange(forSource: titleSource)
        #expect(titleDisplay == NSRange(location: 0, length: 5))
    }

    @Test func sourceRangeForDisplayRangeReverses() {
        let source = "**bold** rest"
        let elides = [
            NSRange(location: 0, length: 2),
            NSRange(location: 6, length: 2)
        ]
        let mapping = DisplayTransform.transform(source: source, elideRanges: elides)
        #expect(mapping.displayString == "bold rest")
        let boldDisplay = NSRange(location: 0, length: 4)
        let boldSource = mapping.sourceRange(forDisplay: boldDisplay)
        #expect(boldSource == NSRange(location: 2, length: 4))
    }

    @Test func overlappingElidesAreMerged() {
        let mapping = DisplayTransform.transform(
            source: "abcdef",
            elideRanges: [
                NSRange(location: 1, length: 2),
                NSRange(location: 2, length: 2)
            ]
        )
        #expect(mapping.displayString == "aef")
    }

    @Test func unsortedElidesAreSorted() {
        let mapping = DisplayTransform.transform(
            source: "abcdef",
            elideRanges: [
                NSRange(location: 4, length: 1),
                NSRange(location: 1, length: 1)
            ]
        )
        #expect(mapping.displayString == "acdf")
    }
}
