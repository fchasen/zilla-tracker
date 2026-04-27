import XCTest
import os
@testable import BugzillaKit

final class ProductsTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testSelectableProductsChainsTwoRequests() async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        MockURLProtocol.handler = { request in
            let n = calls.withLock { value -> Int in
                value += 1
                return value
            }
            switch n {
            case 1:
                XCTAssertEqual(request.url?.path, "/rest/product_selectable")
                let body = #"{"ids":[10,20]}"#.data(using: .utf8)!
                return (httpResponse(for: request, status: 200), body)
            default:
                XCTAssertEqual(request.url?.path, "/rest/product")
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertTrue(items.contains(URLQueryItem(name: "ids", value: "10")))
                XCTAssertTrue(items.contains(URLQueryItem(name: "ids", value: "20")))
                let include = items.first { $0.name == "include_fields" }?.value ?? ""
                XCTAssertTrue(include.contains("components.name"))
                let body = #"""
                {
                  "products": [
                    {
                      "id": 10, "name": "Firefox", "description": "Browser", "is_active": true,
                      "components": [
                        {"id": 1, "name": "General", "description": "top", "default_assigned_to": "a@b", "is_active": true}
                      ]
                    },
                    {"id": 20, "name": "Core", "description": "Engine", "is_active": true, "components": []}
                  ]
                }
                """#.data(using: .utf8)!
                return (httpResponse(for: request, status: 200), body)
            }
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let products = try await client.selectableProducts()
        XCTAssertEqual(products.count, 2)
        XCTAssertEqual(products[0].name, "Firefox")
        XCTAssertEqual(products[0].components.first?.name, "General")
        XCTAssertEqual(products[0].components.first?.defaultAssignedTo, "a@b")
        XCTAssertEqual(products[1].name, "Core")
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    func testEmptySelectableShortCircuits() async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        MockURLProtocol.handler = { request in
            calls.withLock { value in value += 1 }
            return (httpResponse(for: request, status: 200), #"{"ids":[]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let products = try await client.selectableProducts()
        XCTAssertTrue(products.isEmpty)
        XCTAssertEqual(calls.withLock { $0 }, 1, "should not call /rest/product when no ids")
    }

    func testProductsByName() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/product")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "names", value: "Firefox")))
            let body = #"""
            {"products": [{"id": 10, "name": "Firefox", "description": "", "is_active": true, "components": []}]}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 200), body)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let products = try await client.products(names: ["Firefox"])
        XCTAssertEqual(products.first?.id, 10)
    }
}
