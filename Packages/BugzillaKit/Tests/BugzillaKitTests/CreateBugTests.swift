import XCTest
@testable import BugzillaKit

final class CreateBugTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testCreatesBugWithRequiredFields() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["product"] as? String, "Firefox")
            XCTAssertEqual(json["component"] as? String, "General")
            XCTAssertEqual(json["summary"] as? String, "Crash on launch")
            XCTAssertEqual(json["version"] as? String, "unspecified")
            XCTAssertNil(json["description"])
            XCTAssertNil(json["type"])
            XCTAssertNil(json["severity"])
            XCTAssertNil(json["priority"])
            XCTAssertNil(json["assigned_to"])
            XCTAssertNil(json["keywords"])
            XCTAssertNil(json["blocks"])

            return (httpResponse(for: request, status: 200), #"{"id":4242}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let id = try await client.createBug(
            BugCreate(product: "Firefox", component: "General", summary: "Crash on launch")
        )
        XCTAssertEqual(id, 4242)
    }

    func testIncludesDescriptionAndOptionals() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

            XCTAssertEqual(json["description"] as? String, "Steps to reproduce…")
            XCTAssertEqual(json["type"] as? String, "defect")
            XCTAssertEqual(json["severity"] as? String, "S2")
            XCTAssertEqual(json["priority"] as? String, "P2")
            XCTAssertEqual(json["assigned_to"] as? String, "dev@example.com")
            XCTAssertEqual(json["keywords"] as? [String], ["regression", "perf"])
            XCTAssertEqual(json["blocks"] as? [Int], [111, 222])
            XCTAssertEqual(json["depends_on"] as? [Int], [333])
            XCTAssertEqual(json["cc"] as? [String], ["watcher@example.com"])
            XCTAssertEqual(json["version"] as? String, "115")

            return (httpResponse(for: request, status: 200), #"{"id":555}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let id = try await client.createBug(
            BugCreate(
                product: "Core",
                component: "DOM: Core & HTML",
                summary: "Layout regression",
                version: "115",
                description: "Steps to reproduce…",
                type: "defect",
                severity: "S2",
                priority: "P2",
                assignedTo: "dev@example.com",
                keywords: ["regression", "perf"],
                blocks: [111, 222],
                dependsOn: [333],
                cc: ["watcher@example.com"]
            )
        )
        XCTAssertEqual(id, 555)
    }

    func testCreateBugOmitsGroupsWhenEmpty() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNil(json["groups"])
            return (httpResponse(for: request, status: 200), #"{"id":1}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.createBug(
            BugCreate(product: "Firefox", component: "General", summary: "x")
        )
    }

    func testCreateBugSendsGroupsArray() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["groups"] as? [String], ["mozilla-employee-confidential"])
            return (httpResponse(for: request, status: 200), #"{"id":1}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.createBug(
            BugCreate(
                product: "Firefox",
                component: "General",
                summary: "x",
                groups: [BugGroup.mozillaEmployeeConfidential]
            )
        )
    }

    func testReturnsCreatedBugID() async throws {
        MockURLProtocol.handler = { request in
            return (httpResponse(for: request, status: 200), #"{"id":987654}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let id = try await client.createBug(
            BugCreate(product: "Firefox", component: "General", summary: "x")
        )
        XCTAssertEqual(id, 987654)
    }

    func testPropagatesAPIError() async throws {
        MockURLProtocol.handler = { request in
            let body = #"""
            {"error":true,"code":51,"message":"Component does not exist."}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 400), body)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.createBug(
                BugCreate(product: "Bogus", component: "Bogus", summary: "x")
            )
            XCTFail("expected an error")
        } catch BugzillaError.api(let code, let message) {
            XCTAssertEqual(code, 51)
            XCTAssertEqual(message, "Component does not exist.")
        }
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
