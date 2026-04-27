import XCTest
@testable import BugzillaKit

final class CommentsTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testCommentsForBug() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug/1234567/comment")
            let body = #"""
            {
              "bugs": {
                "1234567": {
                  "comments": [
                    {
                      "id": 1, "bug_id": 1234567,
                      "creator": "alice@example.com", "text": "First post",
                      "creation_time": "2024-01-02T03:04:05Z",
                      "is_private": false, "count": 0
                    },
                    {
                      "id": 2, "bug_id": 1234567,
                      "creator": "bob@example.com", "text": "Reply",
                      "creation_time": "2024-01-03T03:04:05Z",
                      "is_private": false, "count": 1
                    }
                  ]
                }
              }
            }
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let comments = try await client.comments(bugID: 1234567)
        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].creator, "alice@example.com")
        XCTAssertEqual(comments[0].text, "First post")
        XCTAssertEqual(comments[1].count, 1)
        XCTAssertEqual(comments[1].bugId, 1234567)
    }

    func testCommentsEmptyForUnknownBug() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"bugs":{}}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let comments = try await client.comments(bugID: 9999999)
        XCTAssertTrue(comments.isEmpty)
    }
}
