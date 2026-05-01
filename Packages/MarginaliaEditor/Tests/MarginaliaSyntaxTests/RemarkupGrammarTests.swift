import XCTest
@testable import MarginaliaSyntax

final class RemarkupGrammarTests: XCTestCase {

    func testRemarkupItalic() {
        let spans = RemarkupGrammar.highlights(in: "this is //italic// text")
        let italic = spans.first { $0.tag == .textEmphasis }
        XCTAssertNotNil(italic)
        XCTAssertEqual(italic?.range.location, 8)
        XCTAssertEqual(italic?.range.length, 10)  // "//italic//"
    }

    func testRevisionAutolink() {
        let spans = RemarkupGrammar.highlights(in: "see D12345 for details")
        let link = spans.first { $0.tag == .textURI }
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.range.location, 4)
        XCTAssertEqual(link?.range.length, 6)
    }

    func testTaskAutolink() {
        let spans = RemarkupGrammar.highlights(in: "fixes T999")
        let link = spans.first { $0.tag == .textURI }
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.range.location, 6)
        XCTAssertEqual(link?.range.length, 4)
    }

    func testFileEmbed() {
        let spans = RemarkupGrammar.highlights(in: "image: {F1234}")
        let embed = spans.first { $0.tag == .textURI }
        XCTAssertNotNil(embed)
    }

    func testPasteEmbed() {
        let spans = RemarkupGrammar.highlights(in: "paste: {P567}")
        let embed = spans.first { $0.tag == .textURI }
        XCTAssertNotNil(embed)
    }

    func testUserMention() {
        let spans = RemarkupGrammar.highlights(in: "cc @alice and @bob.smith")
        let mentions = spans.filter { $0.tag == .textReference }
        XCTAssertEqual(mentions.count, 2)
    }

    func testNoteCallout() {
        let spans = RemarkupGrammar.highlights(in: "NOTE: pay attention")
        let callout = spans.first { $0.tag == .textTitle }
        XCTAssertNotNil(callout)
        XCTAssertEqual(callout?.range.length, 5)  // "NOTE:"
    }

    func testWarningCalloutMidLineNotMatched() {
        // Callouts must be at start of line
        let spans = RemarkupGrammar.highlights(in: "this WARNING: should not match")
        let title = spans.first { $0.tag == .textTitle }
        XCTAssertNil(title)
    }

    func testRemarkupHeading() {
        let spans = RemarkupGrammar.highlights(in: "== title ==")
        let heading = spans.first { $0.tag == .textTitle }
        XCTAssertNotNil(heading)
    }

    func testItalicDoesNotEatAcrossNewline() {
        // // marker at start of line, // never closes — shouldn't span a newline
        let spans = RemarkupGrammar.highlights(in: "//start\nmiddle//")
        let italic = spans.first { $0.tag == .textEmphasis }
        XCTAssertNil(italic)
    }

    func testRevisionAutolinkNotMatchedInWord() {
        // D12 inside identifier shouldn't match
        let spans = RemarkupGrammar.highlights(in: "fooD12bar")
        let link = spans.first { $0.tag == .textURI }
        XCTAssertNil(link)
    }

    func testSpansAreSorted() {
        let spans = RemarkupGrammar.highlights(in: "@user fixes D1 and T2")
        let locations = spans.map { $0.range.location }
        XCTAssertEqual(locations, locations.sorted())
    }
}
