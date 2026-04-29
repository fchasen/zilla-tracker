import XCTest
@testable import BugzillaKit

final class BugSearchTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testGetBugById() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug/1234567")
            let body = #"""
            {"bugs":[
              {"id":1234567,"summary":"Hello","status":"NEW","resolution":"",
               "product":"Firefox","component":"General","keywords":[],
               "blocks":[],"depends_on":[],"cc":[],"flags":[]}
            ]}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let bug = try await client.getBug(id: 1234567)
        XCTAssertEqual(bug.id, 1234567)
        XCTAssertEqual(bug.summary, "Hello")
        XCTAssertEqual(bug.product, "Firefox")
    }

    func testGetBugByIdNotFoundEnvelope() async {
        MockURLProtocol.handler = { request in
            let body = #"{"error":true,"code":101,"message":"Bug 1 does not exist"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 404), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.getBug(id: 1)
            XCTFail("Expected notFound")
        } catch BugzillaError.notFound {
            // ok — 404 short-circuits before we look at the envelope
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testGetBugsByIdsBatches() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "id", value: "1")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "id", value: "2")))
            let body = #"""
            {"bugs":[
              {"id":1,"summary":"a","status":"NEW","resolution":"","product":"P","component":"C",
               "keywords":[],"blocks":[],"depends_on":[],"cc":[],"flags":[]},
              {"id":2,"summary":"b","status":"NEW","resolution":"","product":"P","component":"C",
               "keywords":[],"blocks":[],"depends_on":[],"cc":[],"flags":[]}
            ]}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let bugs = try await client.getBugs(ids: [1, 2])
        XCTAssertEqual(bugs.count, 2)
        XCTAssertEqual(bugs[0].id, 1)
        XCTAssertEqual(bugs[1].id, 2)
    }

    func testSearchMyBugs() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "assigned_to", value: "@me")))
            XCTAssertFalse(items.contains(where: { $0.name == "resolution" }))
            let body = #"{"bugs":[]}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let result = try await client.searchBugs(.myBugs)
        XCTAssertEqual(result.bugs.count, 0)
    }

    func testSearchOpenInComponent() async throws {
        MockURLProtocol.handler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "product", value: "Firefox")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "component", value: "General")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "resolution", value: "---")))
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let ref = ComponentRef(product: "Firefox", component: "General")
        _ = try await client.searchBugs(.openIn(component: ref))
    }

    func testSearchBlockedByMetaBug() async throws {
        MockURLProtocol.handler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "blocks", value: "1700001")))
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.searchBugs(.blockedBy(metaBug: 1700001))
    }

    func testSearchNeedsReviewEmitsBooleanChart() async throws {
        MockURLProtocol.handler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "f1", value: "requestees.login_name")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "o1", value: "equals")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "v1", value: "@me")))
            XCTAssertFalse(items.contains { $0.value == "flagtypes.name" })
            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        _ = try await client.searchBugs(.needsReviewFromMe)
    }

    func testSearchRecentlyChangedEncodesDateAndOrChart() async throws {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        MockURLProtocol.handler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []

            let lastChanged = items.first { $0.name == "last_change_time" }?.value
            XCTAssertEqual(lastChanged, "2023-11-14T22:13:20Z")

            XCTAssertTrue(items.contains(URLQueryItem(name: "f1", value: "OP")))
            XCTAssertTrue(items.contains(URLQueryItem(name: "j1", value: "OR")))
            XCTAssertTrue(items.contains { $0.name.hasPrefix("f") && $0.value == "assigned_to" })
            XCTAssertTrue(items.contains { $0.name.hasPrefix("f") && $0.value == "reporter" })
            XCTAssertTrue(items.contains { $0.name.hasPrefix("f") && $0.value == "cc" })
            XCTAssertTrue(items.contains { $0.name.hasPrefix("f") && $0.value == "commenter" })
            XCTAssertTrue(items.contains { $0.value == "CP" })

            return (httpResponse(for: request, status: 200), #"{"bugs":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let query = BugQuery(changedAfter: cutoff, userInvolved: BugQuery.me)
        _ = try await client.searchBugs(query)
    }

    func testSearchToleratesMissingArrayFields() async throws {
        // BMO honors include_fields by omitting unrequested keys entirely.
        // Decoding must not require blocks/depends_on/cc/flags/keywords.
        MockURLProtocol.handler = { request in
            let body = #"""
            {"bugs":[
              {"id":1234567,"summary":"hi","status":"NEW","resolution":"",
               "product":"Firefox","component":"General",
               "assigned_to":"a@b","last_change_time":"2024-01-02T03:04:05Z"}
            ]}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let result = try await client.searchBugs(BugQuery())
        XCTAssertEqual(result.bugs.count, 1)
        XCTAssertEqual(result.bugs[0].id, 1234567)
        XCTAssertEqual(result.bugs[0].assignedTo, "a@b")
        XCTAssertEqual(result.bugs[0].keywords, [])
        XCTAssertEqual(result.bugs[0].blocks, [])
        XCTAssertEqual(result.bugs[0].dependsOn, [])
        XCTAssertEqual(result.bugs[0].cc, [])
        XCTAssertEqual(result.bugs[0].flags, [])
    }

    func testSearchDecodesTotalMatches() async throws {
        MockURLProtocol.handler = { request in
            let body = #"""
            {"bugs":[
              {"id":1,"summary":"a","status":"NEW","resolution":"","product":"P","component":"C",
               "keywords":[],"blocks":[],"depends_on":[],"cc":[],"flags":[]}
            ],"total_matches":42}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }
        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let result = try await client.searchBugs(BugQuery())
        XCTAssertEqual(result.bugs.count, 1)
        XCTAssertEqual(result.totalMatches, 42)
    }
}
