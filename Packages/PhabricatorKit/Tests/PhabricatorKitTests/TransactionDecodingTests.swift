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
        if case .statusChange(let old, let new) = result.data[1].kind {
            XCTAssertEqual(old, "needs-review")
            XCTAssertEqual(new, "accepted")
        } else {
            XCTFail("Expected .statusChange kind")
        }
    }

    func testDecodesReviewersAddWithOperations() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 5,
                "phid": "PHID-XACT-5",
                "type": "reviewers.add",
                "authorPHID": "PHID-USER-author",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000400,
                "dateModified": 1714000400,
                "comments": [],
                "fields": {
                  "operations": [
                    {"operation": "add", "phid": "PHID-USER-alice", "oldStatus": null, "newStatus": "added", "isBlocking": true},
                    {"operation": "add", "phid": "PHID-USER-bob", "oldStatus": null, "newStatus": "added", "isBlocking": false},
                    {"operation": "remove", "phid": "PHID-USER-carol", "oldStatus": "added", "newStatus": null, "isBlocking": false}
                  ]
                }
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
        let ops = try XCTUnwrap(xact.fields.operations)
        XCTAssertEqual(ops.count, 3)
        XCTAssertEqual(ops[0].phid, "PHID-USER-alice")
        XCTAssertEqual(ops[0].isBlocking, true)
        XCTAssertEqual(ops[1].isBlocking, false)
        XCTAssertEqual(ops[2].operation, "remove")
        XCTAssertTrue(xact.referencedPHIDs.contains("PHID-USER-alice"))
        XCTAssertTrue(xact.referencedPHIDs.contains("PHID-USER-carol"))

        if case .reviewersChanged(let kindOps) = xact.kind {
            XCTAssertEqual(kindOps.count, 3)
        } else {
            XCTFail("Expected .reviewersChanged kind")
        }
    }

    func testDecodesTitleChange() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 6,
                "phid": "PHID-XACT-6",
                "type": "title",
                "authorPHID": "PHID-USER-author",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000500,
                "dateModified": 1714000500,
                "comments": [],
                "fields": {"old": "Old title", "new": "New, improved title"}
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
        if case .titleChange(let old, let new) = xact.kind {
            XCTAssertEqual(old, "Old title")
            XCTAssertEqual(new, "New, improved title")
        } else {
            XCTFail("Expected .titleChange kind")
        }
    }

    func testDecodesBugzillaBugIDChange() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 7,
                "phid": "PHID-XACT-7",
                "type": "bugzilla.bug-id",
                "authorPHID": "PHID-USER-author",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000600,
                "dateModified": 1714000600,
                "comments": [],
                "fields": {"old": "1234567", "new": "7654321"}
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
        if case .bugIDChange(let old, let new) = xact.kind {
            XCTAssertEqual(old, "1234567")
            XCTAssertEqual(new, "7654321")
        } else {
            XCTFail("Expected .bugIDChange kind")
        }
    }

    func testDecodesDiffUpdate() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 8,
                "phid": "PHID-XACT-8",
                "type": "update",
                "authorPHID": "PHID-USER-author",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000700,
                "dateModified": 1714000700,
                "comments": [],
                "fields": {"diff": {"id": 47, "phid": "PHID-DIFF-47"}}
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
        XCTAssertEqual(xact.fields.diffID, 47)
        XCTAssertEqual(xact.fields.diffPHID, "PHID-DIFF-47")
        if case .diffUpdate(let id, let phid) = xact.kind {
            XCTAssertEqual(id, 47)
            XCTAssertEqual(phid, "PHID-DIFF-47")
        } else {
            XCTFail("Expected .diffUpdate kind")
        }
    }

    func testDecodesProjectsAddOperations() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 9,
                "phid": "PHID-XACT-9",
                "type": "projects.add",
                "authorPHID": "PHID-USER-author",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000800,
                "dateModified": 1714000800,
                "comments": [],
                "fields": {
                  "operations": [
                    {"operation": "add", "phid": "PHID-PROJ-aaa"},
                    {"operation": "remove", "phid": "PHID-PROJ-bbb"}
                  ]
                }
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
        if case .projectsChanged(let adds, let removes) = xact.kind {
            XCTAssertEqual(adds, ["PHID-PROJ-aaa"])
            XCTAssertEqual(removes, ["PHID-PROJ-bbb"])
        } else {
            XCTFail("Expected .projectsChanged kind")
        }
        XCTAssertTrue(xact.referencedPHIDs.contains("PHID-PROJ-aaa"))
        XCTAssertTrue(xact.referencedPHIDs.contains("PHID-PROJ-bbb"))
    }

    func testHarbormasterBuildableClassifiesAsBuildStatus() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 11,
                "phid": "PHID-XACT-11",
                "type": "harbormaster:buildable",
                "authorPHID": "PHID-APPS-PhabricatorHarbormasterApplication",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714001000,
                "dateModified": 1714001000,
                "comments": [],
                "fields": {"old": "1", "new": "2"}
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
        if case .buildStatus(let old, let new) = xact.kind {
            XCTAssertEqual(old, "1")
            XCTAssertEqual(new, "2")
        } else {
            XCTFail("Expected .buildStatus kind for harbormaster:buildable")
        }
    }

    func testHarbormasterAuthoredFallsBackToBuildStatus() throws {
        // Some Phabricator forks emit harbormaster transactions without a
        // recognizable type string but author them as the Harbormaster app.
        // We classify those as build events anyway.
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 12,
                "phid": "PHID-XACT-12",
                "type": "harbormaster.synthetic",
                "authorPHID": "PHID-APPS-PhabricatorHarbormasterApplication",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714001100,
                "dateModified": 1714001100,
                "comments": [],
                "fields": {"old": "1", "new": "3"}
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
        if case .buildStatus(let old, let new) = xact.kind {
            XCTAssertEqual(old, "1")
            XCTAssertEqual(new, "3")
        } else {
            XCTFail("Expected .buildStatus fallback for Harbormaster-authored transaction")
        }
    }

    func testSystemActorDisplayNames() {
        XCTAssertEqual(
            SystemActor.displayName(forPHID: "PHID-APPS-PhabricatorHarbormasterApplication"),
            "Harbormaster"
        )
        XCTAssertEqual(
            SystemActor.displayName(forPHID: "PHID-APPS-PhabricatorHeraldApplication"),
            "Herald"
        )
        XCTAssertEqual(
            SystemActor.displayName(forPHID: "PHID-APPS-PhabricatorDiffusionApplication"),
            "Diffusion"
        )
        XCTAssertNil(SystemActor.displayName(forPHID: "PHID-USER-alice"))
    }

    func testAcceptVerbKindClassification() throws {
        let json = """
        {
          "result": {
            "data": [
              {
                "id": 10,
                "phid": "PHID-XACT-10",
                "type": "accept",
                "authorPHID": "PHID-USER-x",
                "objectPHID": "PHID-DREV-abc",
                "dateCreated": 1714000900,
                "dateModified": 1714000900,
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
        if case .verb(.accept) = xact.kind {
            // ok
        } else {
            XCTFail("Expected .verb(.accept) kind")
        }
    }
}
