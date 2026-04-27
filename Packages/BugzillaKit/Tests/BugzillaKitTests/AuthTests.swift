import XCTest
@testable import BugzillaKit

final class AuthTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testLoginHappyPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/login")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "login", value: "alice@example.com")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "api_key", value: "secret")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "restrict_login", value: "true")))
            let body = #"{"id":42,"token":"abc-123"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let auth = try await client.login(name: "alice@example.com", apiKey: "secret")

        guard case .token(let token, let id) = auth else {
            return XCTFail("Expected token authentication, got \(auth)")
        }
        XCTAssertEqual(token, "abc-123")
        XCTAssertEqual(id, 42)

        let stored = await client.authentication
        XCTAssertEqual(stored, auth)
    }

    func testLoginRestrictDisabled() async throws {
        MockURLProtocol.handler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "restrict_login", value: "false")))
            return (httpResponse(for: request, status: 200), #"{"id":1,"token":"t"}"#.data(using: .utf8)!)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.login(name: "a", apiKey: "k", restrictToIP: false)
    }

    func testLoginInvalidApiKey() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":true,"code":306,"message":"The API key you specified is invalid."}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 400), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.login(name: "alice", apiKey: "bad")
            XCTFail("Expected api error")
        } catch BugzillaError.api(let code, _) {
            XCTAssertEqual(code, 306)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testWhoamiDecodesAllFields() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/whoami")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-BUGZILLA-API-KEY"), "k")
            let body = #"{"id":42,"name":"alice@example.com","real_name":"Alice","nick":"alice"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(
            baseURL: baseURL,
            authentication: .apiKey("k"),
            session: MockURLProtocol.session()
        )
        let user = try await client.whoami()
        XCTAssertEqual(user.id, 42)
        XCTAssertEqual(user.name, "alice@example.com")
        XCTAssertEqual(user.realName, "Alice")
        XCTAssertEqual(user.nick, "alice")
    }

    func testTokenAuthSendsHeader() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-BUGZILLA-TOKEN"), "tok-1")
            let body = #"{"id":1,"name":"a"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(
            baseURL: baseURL,
            authentication: .token("tok-1", userID: 1),
            session: MockURLProtocol.session()
        )
        _ = try await client.whoami()
    }

    func testValidLoginTrue() async throws {
        MockURLProtocol.handler = { request in
            (httpResponse(for: request, status: 200), #"{"id":1,"name":"a"}"#.data(using: .utf8)!)
        }
        let client = BugzillaClient(
            baseURL: baseURL,
            authentication: .apiKey("k"),
            session: MockURLProtocol.session()
        )
        let valid = try await client.validLogin()
        XCTAssertTrue(valid)
    }

    func testValidLoginFalseOnUnauthorized() async throws {
        MockURLProtocol.handler = { request in
            (httpResponse(for: request, status: 401), Data())
        }
        let client = BugzillaClient(
            baseURL: baseURL,
            authentication: .apiKey("bad"),
            session: MockURLProtocol.session()
        )
        let valid = try await client.validLogin()
        XCTAssertFalse(valid)
    }

    func testLogoutClearsAuth() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/logout")
            return (httpResponse(for: request, status: 200), "{}".data(using: .utf8))
        }
        let client = BugzillaClient(
            baseURL: baseURL,
            authentication: .token("abc", userID: 1),
            session: MockURLProtocol.session()
        )
        try await client.logout()
        let stored = await client.authentication
        XCTAssertEqual(stored, .none)
    }
}
