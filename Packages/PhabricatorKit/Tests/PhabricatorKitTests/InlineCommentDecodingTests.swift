import XCTest
@testable import PhabricatorKit

final class InlineCommentDecodingTests: XCTestCase {
    func testDecodesPublishedAndDraftInlines() throws {
        let json = """
        {
          "result": [
            {
              "id": "100",
              "phid": "PHID-XCMT-100",
              "authorPHID": "PHID-USER-alice",
              "diffID": "999000",
              "filePath": "src/foo.swift",
              "lineNumber": "42",
              "lineLength": "1",
              "isNewFile": "1",
              "isDeleted": "0",
              "replyToCommentPHID": null,
              "transactionPHID": "PHID-XACT-1",
              "content": "Nit: rename this.",
              "dateCreated": 1714000000,
              "dateModified": 1714000005
            },
            {
              "id": "101",
              "phid": "PHID-XCMT-101",
              "authorPHID": "PHID-USER-self",
              "diffID": "999000",
              "filePath": "src/foo.swift",
              "lineNumber": "44",
              "lineLength": "3",
              "isNewFile": "1",
              "isDeleted": "0",
              "replyToCommentPHID": null,
              "transactionPHID": null,
              "content": "Draft from me",
              "dateCreated": 1714000099,
              "dateModified": 1714000099
            }
          ],
          "error_code": null,
          "error_info": null
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<[DifferentialGetInlinesRaw]>.self, from: json)
        let raws = try XCTUnwrap(envelope.result)
        let inlines = raws.map { $0.toModel() }

        XCTAssertEqual(inlines.count, 2)
        XCTAssertEqual(inlines[0].path, "src/foo.swift")
        XCTAssertEqual(inlines[0].line, 42)
        XCTAssertEqual(inlines[0].length, 1)
        XCTAssertTrue(inlines[0].isNewFile)
        XCTAssertNotNil(inlines[0].transactionPHID)
        XCTAssertFalse(inlines[0].isDraft)

        XCTAssertEqual(inlines[1].length, 3)
        XCTAssertNil(inlines[1].transactionPHID)
        XCTAssertTrue(inlines[1].isDraft)
    }

    func testDecodesReplyInline() throws {
        let json = """
        {
          "result": [
            {
              "id": "200",
              "phid": "PHID-XCMT-200",
              "authorPHID": "PHID-USER-self",
              "diffID": "999000",
              "filePath": "src/foo.swift",
              "lineNumber": "10",
              "lineLength": "1",
              "isNewFile": "0",
              "isDeleted": "0",
              "replyToCommentPHID": "PHID-XCMT-100",
              "transactionPHID": null,
              "content": "Replying to your comment",
              "dateCreated": 1714000200,
              "dateModified": 1714000200
            }
          ],
          "error_code": null
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<[DifferentialGetInlinesRaw]>.self, from: json)
        let raws = try XCTUnwrap(envelope.result)
        let inline = raws[0].toModel()
        XCTAssertEqual(inline.replyToCommentPHID, "PHID-XCMT-100")
        XCTAssertFalse(inline.isNewFile)
        XCTAssertTrue(inline.isDraft)
    }
}
