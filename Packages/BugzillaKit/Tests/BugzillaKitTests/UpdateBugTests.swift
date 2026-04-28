import XCTest
@testable import BugzillaKit

final class UpdateBugTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testResolveAsFixed() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug/1234567")
            XCTAssertEqual(request.httpMethod, "PUT")

            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["status"] as? String, "RESOLVED")
            XCTAssertEqual(json["resolution"] as? String, "FIXED")
            XCTAssertNil(json["dupe_of"])
            XCTAssertNil(json["comment"])

            let response = #"""
            {"bugs":[
              {"id":1234567,"last_change_time":"2024-01-02T03:04:05Z",
               "changes":{
                 "status":{"removed":"NEW","added":"RESOLVED"},
                 "resolution":{"removed":"","added":"FIXED"}
               }}
            ]}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), response)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let results = try await client.updateBug(
            id: 1234567,
            BugUpdate(status: "RESOLVED", resolution: "FIXED")
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, 1234567)
        XCTAssertEqual(results[0].changes["status"]?.added, "RESOLVED")
        XCTAssertEqual(results[0].changes["resolution"]?.added, "FIXED")
    }

    func testResolveAsDuplicateSendsDupeOf() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["status"] as? String, "RESOLVED")
            XCTAssertEqual(json["resolution"] as? String, "DUPLICATE")
            XCTAssertEqual(json["dupe_of"] as? Int, 999)

            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(
            id: 1,
            BugUpdate(status: "RESOLVED", resolution: "DUPLICATE", dupeOf: 999)
        )
    }

    func testUpdateWithCommentNestsBodyAndPrivacy() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let comment = try XCTUnwrap(json["comment"] as? [String: Any])
            XCTAssertEqual(comment["body"] as? String, "Marking duplicate per triage.")
            XCTAssertEqual(comment["is_private"] as? Bool, false)
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(
            id: 1,
            BugUpdate(
                status: "RESOLVED",
                resolution: "DUPLICATE",
                dupeOf: 999,
                comment: "Marking duplicate per triage.",
                commentIsPrivate: false
            )
        )
    }

    func testEmptyUpdateOmitsAllFields() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertTrue(json.isEmpty, "no fields should be encoded for an empty update")
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(id: 1, BugUpdate())
    }
}

private extension URLRequest {
    var bodyData: Data? {
        if let direct = httpBody { return direct }
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
