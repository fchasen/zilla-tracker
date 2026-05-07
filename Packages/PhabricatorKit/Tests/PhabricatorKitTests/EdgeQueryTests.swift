import XCTest
@testable import PhabricatorKit

final class EdgeQueryTests: XCTestCase {
    func testStackEdgeConduitTypeNames() {
        XCTAssertEqual(RevisionStackEdge.parentsOfSource.conduitTypeName, "revision.parent")
        XCTAssertEqual(RevisionStackEdge.childrenOfSource.conduitTypeName, "revision.child")
        XCTAssertEqual(RevisionStackEdge.from(conduitTypeName: "revision.parent"), .parentsOfSource)
        XCTAssertEqual(RevisionStackEdge.from(conduitTypeName: "revision.child"), .childrenOfSource)
        XCTAssertEqual(RevisionStackEdge.from(conduitTypeName: "5"), .parentsOfSource)
        XCTAssertEqual(RevisionStackEdge.from(conduitTypeName: "6"), .childrenOfSource)
        XCTAssertNil(RevisionStackEdge.from(conduitTypeName: "bogus.key"))
    }

    func testEncodesSourcePHIDsAndTypes() throws {
        let query = EdgeQuery(
            sourcePHIDs: ["PHID-DREV-aaa", "PHID-DREV-bbb"],
            types: [.parentsOfSource, .childrenOfSource]
        )
        let encoder = PhabricatorClient.makeEncoder()
        let data = try encoder.encode(query)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\"sourcePHIDs\":[\"PHID-DREV-aaa\",\"PHID-DREV-bbb\"]"), s)
        XCTAssertTrue(s.contains("\"types\":[\"revision.parent\",\"revision.child\"]"), s)
        XCTAssertTrue(s.contains("\"limit\":100"), s)
    }

    func testWrapParamsIncludesConduitToken() throws {
        let query = EdgeQuery(
            sourcePHIDs: ["PHID-DREV-aaa"],
            types: [.childrenOfSource]
        )
        let json = try PhabricatorClient.wrapParams(query, token: "api-xyz", encoder: PhabricatorClient.makeEncoder())
        XCTAssertTrue(json.contains("\"sourcePHIDs\":[\"PHID-DREV-aaa\"]"), json)
        XCTAssertTrue(json.contains("\"types\":[\"revision.child\"]"), json)
        XCTAssertTrue(json.contains("\"__conduit__\""), json)
    }

    func testDecodesEdgeSearchResult() throws {
        let json = """
        {
            "data": [
                {
                    "sourcePHID": "PHID-DREV-aaa",
                    "destinationPHID": "PHID-DREV-bbb",
                    "edgeType": "revision.parent"
                },
                {
                    "sourcePHID": "PHID-DREV-aaa",
                    "destinationPHID": "PHID-DREV-ccc",
                    "edgeType": 6
                }
            ],
            "cursor": { "limit": 100, "after": null, "before": null }
        }
        """
        let data = Data(json.utf8)
        let result = try PhabricatorClient.makeDecoder().decode(EdgeSearchResult.self, from: data)
        XCTAssertEqual(result.data.count, 2)
        XCTAssertEqual(result.data[0].sourcePHID, "PHID-DREV-aaa")
        XCTAssertEqual(result.data[0].destinationPHID, "PHID-DREV-bbb")
        XCTAssertEqual(result.data[0].edgeType, "revision.parent")
        XCTAssertEqual(result.data[1].edgeType, "6")
    }
}
