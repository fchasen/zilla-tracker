import XCTest
@testable import BugzillaKit

final class BugzillaKitTests: XCTestCase {
    func testClientInitializes() {
        let client = BugzillaClient(
            baseURL: URL(string: "https://bugzilla.mozilla.org")!
        )
        XCTAssertNotNil(client)
    }

    func testBugQueryPresets() {
        XCTAssertEqual(BugQuery.myOpenBugs.assignedTo, ["@me"])
        XCTAssertEqual(BugQuery.myOpenBugs.resolution, ["---"])
        XCTAssertEqual(BugQuery.reportedByMe.reporter, ["@me"])

        let ref = ComponentRef(product: "Firefox", component: "General")
        let q = BugQuery.openIn(component: ref)
        XCTAssertEqual(q.product, ["Firefox"])
        XCTAssertEqual(q.component, ["General"])
        XCTAssertEqual(q.resolution, ["---"])
    }

    func testMetaBugDetection() {
        let bug = Bug(
            id: 1,
            summary: "Tracking bug",
            status: "NEW",
            resolution: "",
            product: "Firefox",
            component: "General",
            keywords: ["meta"]
        )
        XCTAssertTrue(bug.isMeta)
    }
}
