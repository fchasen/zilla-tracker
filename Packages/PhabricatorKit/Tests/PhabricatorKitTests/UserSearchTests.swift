import Foundation
import XCTest
@testable import PhabricatorKit

final class UserSearchTests: XCTestCase {
    func testSearchUsersUsesUserSearchAndDecodesRows() async throws {
        let transport = RecordingTransport(
            data: """
            {
              "result": {
                "data": [
                  {
                    "phid": "PHID-USER-fc",
                    "fields": {
                      "username": "fchasen",
                      "realName": "Fred Chasen",
                      "image": "https://example.com/avatar.png"
                    }
                  }
                ]
              },
              "error_code": null,
              "error_info": null
            }
            """.data(using: .utf8)!
        )
        let client = PhabricatorClient(
            baseURL: URL(string: "https://phabricator.example.com")!,
            authentication: .apiToken("api-test"),
            transport: transport
        )

        let users = try await client.searchUsers(query: "fcha", limit: 5)

        XCTAssertEqual(users.map { $0.userName }, ["fchasen"])
        XCTAssertEqual(users.first?.realName, "Fred Chasen")
        XCTAssertEqual(users.first?.image?.absoluteString, "https://example.com/avatar.png")

        let capturedRequest = await transport.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://phabricator.example.com/api/user.search")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("api.token=api-test"), body)
        XCTAssertTrue(body.contains("%22query%22%3A%22fcha%22"), body)
        XCTAssertTrue(body.contains("%22limit%22%3A5"), body)
    }

    func testSearchUsersSkipsBlankQuery() async throws {
        let transport = RecordingTransport(data: Data())
        let client = PhabricatorClient(
            baseURL: URL(string: "https://phabricator.example.com")!,
            authentication: .apiToken("api-test"),
            transport: transport
        )

        let users = try await client.searchUsers(query: "   ")

        XCTAssertTrue(users.isEmpty)
        let capturedRequest = await transport.capturedRequest()
        XCTAssertNil(capturedRequest)
    }
}

private actor RecordingTransport: Transport {
    private(set) var request: URLRequest?
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func capturedRequest() -> URLRequest? {
        request
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
