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

    func testReviewingQueryConstrainsByResponsibleAndNeedsReview() throws {
        let query = RevisionQuery.reviewing(responsiblePHID: "PHID-USER-bbb")
        XCTAssertEqual(query.constraints?.responsiblePHIDs, ["PHID-USER-bbb"])
        XCTAssertEqual(query.constraints?.statuses, [RevisionStatus.Value.needsReview])
        XCTAssertEqual(query.attachments?.reviewers, true)
    }

    func testLandedQueryConstrainsByAuthorPublishedAndModifiedStart() throws {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let query = RevisionQuery.landed(authorPHID: "PHID-USER-aaa", since: since)
        XCTAssertEqual(query.constraints?.authorPHIDs, ["PHID-USER-aaa"])
        XCTAssertEqual(query.constraints?.statuses, [RevisionStatus.Value.published])
        XCTAssertEqual(query.constraints?.modifiedStart, 1_700_000_000)
    }

    func testFormBodyEncodesTokenAndParams() throws {
        let body = ConduitFormBody.encode(token: "api-xyz", paramsJSON: "{\"order\":\"updated\"}")
        let s = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("api.token=api-xyz"))
        XCTAssertTrue(s.contains("params=%7B%22order%22%3A%22updated%22%7D"))
    }

    func testFormBodyOmitsEmptyParamsButKeepsToken() throws {
        let body = ConduitFormBody.encode(token: "api-xyz", paramsJSON: "{}")
        XCTAssertEqual(String(data: body, encoding: .utf8) ?? "", "api.token=api-xyz")
    }

    func testFormBodyOmitsBothWhenAbsent() throws {
        XCTAssertEqual(ConduitFormBody.encode(token: nil, paramsJSON: nil), Data())
        XCTAssertEqual(ConduitFormBody.encode(token: nil, paramsJSON: "{}"), Data())
    }

    func testWrapParamsInjectsConduitToken() throws {
        struct Empty: Encodable {}
        let encoder = PhabricatorClient.makeEncoder()
        let json = try PhabricatorClient.wrapParams(Empty(), token: "api-xyz", encoder: encoder)
        XCTAssertTrue(json.contains("\"__conduit__\""))
        XCTAssertTrue(json.contains("\"token\":\"api-xyz\""))
    }

    func testWrapParamsPreservesExistingFields() throws {
        let query = RevisionQuery.active(authorPHID: "PHID-USER-aaa")
        let encoder = PhabricatorClient.makeEncoder()
        let json = try PhabricatorClient.wrapParams(query, token: "api-xyz", encoder: encoder)
        XCTAssertTrue(json.contains("\"__conduit__\""))
        XCTAssertTrue(json.contains("\"order\":\"updated\""))
        XCTAssertTrue(json.contains("\"authorPHIDs\":[\"PHID-USER-aaa\"]"))
    }

    func testWrapParamsOmitsConduitWhenNoToken() throws {
        struct Empty: Encodable {}
        let encoder = PhabricatorClient.makeEncoder()
        let json = try PhabricatorClient.wrapParams(Empty(), token: nil, encoder: encoder)
        XCTAssertFalse(json.contains("__conduit__"))
        XCTAssertEqual(json, "{}")
    }
}
