import XCTest
@testable import PhabricatorKit

final class TransactionDecodingTests: XCTestCase {
    func testDecodesCommentTransaction() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 1,
                "phid": "PHID-XACT-1",
                "type": "comment",
                "authorPHID": "PHID-USER-bob",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000000,
                "dateModified": 1714000005,
                "comments": [
                  {
                    "id": 11,
                    "phid": "PHID-XCMT-1",
                    "version": 1,
                    "authorPHID": "PHID-USER-bob",
                    "dateCreated": 1714000000,
                    "dateModified": 1714000000,
                    "removed": false,
                    "content": {"raw": "lgtm"}
                  }
                ],
                "fields": {}
              }
            ],
            "cursor": {"limit": 100, "after": null, "before": null}
          },
          "error_code": null,
          "error_info": null
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<TransactionSearchResult>.self, from: json)
        let result = try XCTUnwrap(envelope.result)
        let xact = result.data[0]
        XCTAssertEqual(xact.type, "comment")
        XCTAssertEqual(xact.authorPHID, "PHID-USER-bob")
        XCTAssertEqual(xact.comments.count, 1)
        XCTAssertEqual(xact.comments[0].content.raw, "lgtm")
    }

    func testDecodesAcceptTransaction() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 2,
                "phid": "PHID-XACT-2",
                "type": "accept",
                "authorPHID": "PHID-USER-alice",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000100,
                "dateModified": 1714000100,
                "comments": [],
                "fields": {}
              }
            ],
            "cursor": {"limit": 100, "after": null, "before": null}
          },
          "error_code": null,
          "error_info": null
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<TransactionSearchResult>.self, from: json)
        let xact = try XCTUnwrap(envelope.result?.data.first)
        XCTAssertEqual(xact.type, "accept")
        XCTAssertEqual(xact.authorPHID, "PHID-USER-alice")
        XCTAssertEqual(xact.comments.count, 0)
    }

    func testDecodesReviewersAndStatusTransactions() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 3,
                "phid": "PHID-XACT-3",
                "type": "reviewers.set",
                "authorPHID": "PHID-USER-carol",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000200,
                "dateModified": 1714000200,
                "comments": [],
                "fields": {"old": "", "new": "PHID-USER-x"}
              },
              {
                "id": 4,
                "phid": "PHID-XACT-4",
                "type": "status",
                "authorPHID": "PHID-USER-carol",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000300,
                "dateModified": 1714000300,
                "comments": [],
                "fields": {"old": "needs-review", "new": "accepted"}
              }
            ],
            "cursor": {"limit": 100, "after": null, "before": null}
          },
          "error_code": null,
          "error_info": null
        }
        """.data(using: .utf8)!
        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<TransactionSearchResult>.self, from: json)
        let result = try XCTUnwrap(envelope.result)
        XCTAssertEqual(result.data.count, 2)
        XCTAssertEqual(result.data[0].type, "reviewers.set")
        XCTAssertEqual(result.data[1].type, "status")
        XCTAssertEqual(result.data[1].fields.oldValue, "needs-review")
        XCTAssertEqual(result.data[1].fields.newValue, "accepted")
    }
}
