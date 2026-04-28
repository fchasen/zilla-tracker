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

    func testAddCommentHappyPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug/1234567/comment")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["comment"] as? String, "Looks like a duplicate.")
            XCTAssertEqual(json["is_private"] as? Bool, false)

            let responseBody = #"{"id":42}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 201), responseBody)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let id = try await client.addComment(bugID: 1234567, text: "Looks like a duplicate.")
        XCTAssertEqual(id, 42)
    }

    func testAddCommentSendsMarkdownFlag() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["is_markdown"] as? Bool, true)
            XCTAssertEqual(json["comment"] as? String, "**bold** _italic_")
            return (httpResponse(for: request, status: 201), #"{"id":1}"#.data(using: .utf8)!)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.addComment(bugID: 1, text: "**bold** _italic_", isMarkdown: true)
    }

    func testAddCommentSendsPrivateFlag() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["is_private"] as? Bool, true)
            return (httpResponse(for: request, status: 201), #"{"id":1}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.addComment(bugID: 1, text: "secret", isPrivate: true)
    }

    func testAddCommentSurfacesApiError() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":true,"code":105,"message":"You did not specify a comment"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 400), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.addComment(bugID: 1, text: "")
            XCTFail("Expected api error")
        } catch BugzillaError.api(let code, _) {
            XCTAssertEqual(code, 105)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}

private extension URLRequest {
    /// MockURLProtocol gives us the request as URLSession passes it; httpBody is nil
    /// because URLProtocol exposes the body via `httpBodyStream`. Read it out.
    var bodyData: Data? {
        if let direct = httpBody {
            return direct
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
