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

    func testUpdateSummaryEncodesField() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug/1234567")
            XCTAssertEqual(request.httpMethod, "PUT")

            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["summary"] as? String, "Tab bar disappears in private windows")
            XCTAssertNil(json["status"])
            XCTAssertNil(json["resolution"])

            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(
            id: 1234567,
            BugUpdate(summary: "Tab bar disappears in private windows")
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

    func testAddBlocksUsesAddObject() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let blocks = try XCTUnwrap(json["blocks"] as? [String: Any])
            XCTAssertEqual(blocks["add"] as? [Int], [42])
            XCTAssertNil(blocks["remove"])
            XCTAssertNil(blocks["set"])
            XCTAssertNil(json["depends_on"])
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(
            id: 1,
            BugUpdate(blocks: BugRelationUpdate(add: [42]))
        )
    }

    func testAddGroupsSendsAddArray() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let groups = try XCTUnwrap(json["groups"] as? [String: Any])
            XCTAssertEqual(groups["add"] as? [String], ["mozilla-employee-confidential"])
            XCTAssertNil(groups["remove"])
            XCTAssertNil(groups["set"])
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(
            id: 1,
            BugUpdate(groups: .add([BugGroup.mozillaEmployeeConfidential]))
        )
    }

    func testRemoveGroupsSendsRemoveArray() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let groups = try XCTUnwrap(json["groups"] as? [String: Any])
            XCTAssertEqual(groups["remove"] as? [String], ["mozilla-employee-confidential"])
            XCTAssertNil(groups["add"])
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(
            id: 1,
            BugUpdate(groups: .remove([BugGroup.mozillaEmployeeConfidential]))
        )
    }

    func testAddDependsOnUsesSnakeCaseKey() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let dependsOn = try XCTUnwrap(json["depends_on"] as? [String: Any])
            XCTAssertEqual(dependsOn["add"] as? [Int], [99])
            XCTAssertNil(json["blocks"])
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.updateBug(
            id: 1,
            BugUpdate(dependsOn: .add([99]))
        )
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
