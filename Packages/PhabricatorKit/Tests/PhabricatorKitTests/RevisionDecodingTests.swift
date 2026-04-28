import XCTest
@testable import PhabricatorKit

final class RevisionDecodingTests: XCTestCase {
    func testDecodesRevisionSearchEnvelope() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 12345,
                "type": "DREV",
                "phid": "PHID-DREV-abcdef",
                "fields": {
                  "title": "Bug 1234567 - Make the thing better",
                  "uri": "https://phabricator.services.mozilla.com/D12345",
                  "authorPHID": "PHID-USER-aaa",
                  "status": {
                    "value": "needs-review",
                    "name": "Needs Review",
                    "closed": false,
                    "color.ansi": "magenta"
                  },
                  "summary": "A short summary.",
                  "isDraft": false,
                  "dateCreated": 1714000000,
                  "dateModified": 1714500000,
                  "bugzilla.bug-id": "1234567"
                },
                "attachments": {}
              }
            ],
            "cursor": {
              "limit": 100,
              "after": null,
              "before": null,
              "order": null
            }
          },
          "error_code": null,
          "error_info": null
        }
        """.data(using: .utf8)!

        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<RevisionSearchResult>.self, from: json)
        XCTAssertNil(envelope.errorCode)
        let result = try XCTUnwrap(envelope.result)
        XCTAssertEqual(result.data.count, 1)
        let revision = result.data[0]
        XCTAssertEqual(revision.id, 12345)
        XCTAssertEqual(revision.phid, "PHID-DREV-abcdef")
        XCTAssertEqual(revision.fields.title, "Bug 1234567 - Make the thing better")
        XCTAssertEqual(revision.fields.status.value, "needs-review")
        XCTAssertEqual(revision.fields.status.color, "magenta")
        XCTAssertFalse(revision.fields.status.closed)
        XCTAssertEqual(revision.fields.bugzillaBugID, "1234567")
        XCTAssertEqual(revision.fields.dateModified.timeIntervalSince1970, 1714500000)
    }

    func testDecodesAPIErrorEnvelope() throws {
        let json = """
        {
          "result": null,
          "error_code": "ERR-INVALID-AUTH",
          "error_info": "API token is bad."
        }
        """.data(using: .utf8)!

        let decoder = PhabricatorClient.makeDecoder()
        let envelope = try decoder.decode(ConduitEnvelope<RevisionSearchResult>.self, from: json)
        XCTAssertNil(envelope.result)
        XCTAssertEqual(envelope.errorCode, "ERR-INVALID-AUTH")
    }

    func testActiveQueryConstrainsByAuthorAndOpenStatuses() throws {
        let query = RevisionQuery.active(authorPHID: "PHID-USER-aaa")
        XCTAssertEqual(query.constraints?.authorPHIDs, ["PHID-USER-aaa"])
        XCTAssertEqual(query.constraints?.statuses, RevisionStatus.Value.openValues)
        XCTAssertEqual(query.order, "updated")
    }

    func testReviewingQueryConstrainsByReviewerAndNeedsReview() throws {
        let query = RevisionQuery.reviewing(reviewerPHID: "PHID-USER-bbb")
        XCTAssertEqual(query.constraints?.reviewerPHIDs, ["PHID-USER-bbb"])
        XCTAssertEqual(query.constraints?.statuses, [RevisionStatus.Value.needsReview])
    }

    func testFormBodyEncodesTokenAndJSON() throws {
        let body = ConduitFormBody.encode(token: "api-xyz", paramsJSON: "{\"order\":\"updated\"}")
        let s = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("api.token=api-xyz"))
        XCTAssertTrue(s.contains("output=json"))
        XCTAssertTrue(s.contains("params="))
        XCTAssertTrue(s.contains("%7B%22order%22%3A%22updated%22%7D"))
    }
}
