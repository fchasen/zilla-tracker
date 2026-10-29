import Foundation
import XCTest
@testable import PhabricatorKit

final class CreateInlineEncodingTests: XCTestCase {
    func testCreateInlineSendsOnlyParametersConduitDefines() async throws {
        let transport = RecordingTransport(response: """
        {"result":{"id":"7","phid":"PHID-XCMT-7","authorPHID":"PHID-USER-me","diffID":"55",\
        "filePath":"a.js","lineNumber":"10","lineLength":"2","isNewFile":"1","content":"hi"},\
        "error_code":null,"error_info":null}
        """)
        let client = PhabricatorClient(
            baseURL: URL(string: "https://phabricator.example.com")!,
            authentication: .apiToken("api-test"),
            transport: transport
        )

        let inline = try await client.createInlineComment(
            diffID: 55,
            path: "a.js",
            line: 10,
            length: 3,
            isNewFile: true,
            content: "hi"
        )

        XCTAssertEqual(inline.phid, "PHID-XCMT-7")
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/differential.createinline"])
        let params = try Self.params(of: requests[0])
        XCTAssertEqual(
            Set(params.keys),
            ["__conduit__", "diffID", "filePath", "lineNumber", "lineLength", "isNewFile", "content"]
        )
        XCTAssertEqual(params["lineLength"] as? Int, 2)
    }

    private static func params(of request: URLRequest) throws -> [String: Any] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let pairs = body.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1) }
        let raw = try XCTUnwrap(pairs.first { $0.first == "params" }?.last)
        let json = try XCTUnwrap(String(raw).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}

private actor RecordingTransport: Transport {
    private(set) var requests: [URLRequest] = []
    private let response: String

    init(response: String) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(response.utf8), http)
    }
}
