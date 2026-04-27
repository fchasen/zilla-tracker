import XCTest
@testable import BugzillaKit

final class VersionTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testVersionHappyPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/version")
            XCTAssertEqual(request.httpMethod, "GET")
            let body = #"{"version":"5.0.6"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let version = try await client.version()
        XCTAssertEqual(version, "5.0.6")
    }

    func testUnauthorized() async {
        MockURLProtocol.handler = { request in
            (httpResponse(for: request, status: 401), Data())
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.version()
            XCTFail("Expected unauthorized")
        } catch BugzillaError.unauthorized {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testNotFound() async {
        MockURLProtocol.handler = { request in
            (httpResponse(for: request, status: 404), Data())
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.version()
            XCTFail("Expected notFound")
        } catch BugzillaError.notFound {
            // ok
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testRateLimitedWithRetryAfter() async {
        MockURLProtocol.handler = { request in
            let response = httpResponse(for: request, status: 429, headers: ["Retry-After": "30"])
            return (response, Data())
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.version()
            XCTFail("Expected rateLimited")
        } catch BugzillaError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 30)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testErrorEnvelopeOn200() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":true,"code":32000,"message":"object not found"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.version()
            XCTFail("Expected api error")
        } catch BugzillaError.api(let code, let message) {
            XCTAssertEqual(code, 32000)
            XCTAssertEqual(message, "object not found")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testErrorEnvelopeOn500() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":true,"code":50000,"message":"boom"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 500), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.version()
            XCTFail("Expected api error")
        } catch BugzillaError.api(let code, let message) {
            XCTAssertEqual(code, 50000)
            XCTAssertEqual(message, "boom")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testApiKeyHeaderSent() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-BUGZILLA-API-KEY"), "secret")
            let body = #"{"version":"5.0.6"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(
            baseURL: baseURL,
            authentication: .apiKey("secret"),
            session: MockURLProtocol.session()
        )
        _ = try await client.version()
    }
}
