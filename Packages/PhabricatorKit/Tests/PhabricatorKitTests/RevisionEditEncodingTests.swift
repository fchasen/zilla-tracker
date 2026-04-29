import XCTest
@testable import PhabricatorKit

final class RevisionEditEncodingTests: XCTestCase {
    func testActionAndCommentEncodeAsArray() throws {
        let txs: [RevisionEditTransaction] = [
            .action(.accept),
            .comment("lgtm")
        ]
        let encoder = PhabricatorClient.makeEncoder()
        let data = try encoder.encode(txs)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\"type\":\"accept\""), s)
        XCTAssertTrue(s.contains("\"value\":true"), s)
        XCTAssertTrue(s.contains("\"type\":\"comment\""), s)
        XCTAssertTrue(s.contains("\"value\":\"lgtm\""), s)
    }

    func testWrapParamsRoundTripsEdit() throws {
        struct EditPayload: Encodable {
            let objectIdentifier: String
            let transactions: [RevisionEditTransaction]
        }
        let payload = EditPayload(
            objectIdentifier: "PHID-DREV-abc",
            transactions: [.action(.accept), .comment("lgtm")]
        )
        let json = try PhabricatorClient.wrapParams(payload, token: "api-xyz", encoder: PhabricatorClient.makeEncoder())
        XCTAssertTrue(json.contains("\"objectIdentifier\":\"PHID-DREV-abc\""), json)
        XCTAssertTrue(json.contains("\"type\":\"accept\""), json)
        XCTAssertTrue(json.contains("\"value\":true"), json)
        XCTAssertTrue(json.contains("\"type\":\"comment\""), json)
        XCTAssertTrue(json.contains("\"value\":\"lgtm\""), json)
        XCTAssertTrue(json.contains("\"__conduit__\""), json)
    }

    func testPlanChangesUsesHyphenatedRawValue() throws {
        XCTAssertEqual(RevisionAction.planChanges.rawValue, "plan-changes")
        XCTAssertEqual(RevisionAction.requestReview.rawValue, "request-review")
        let tx = RevisionEditTransaction.action(.planChanges)
        let data = try PhabricatorClient.makeEncoder().encode(tx)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\"type\":\"plan-changes\""), s)
    }
}
