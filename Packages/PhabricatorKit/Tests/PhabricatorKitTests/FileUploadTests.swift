import Foundation
import XCTest
@testable import PhabricatorKit

final class FileUploadTests: XCTestCase {
    func testUploadFileUploadsThenResolvesID() async throws {
        let transport = SequencedTransport(responses: [
            #"{"result":"PHID-FILE-abc","error_code":null,"error_info":null}"#,
            #"{"result":{"data":[{"id":4321,"phid":"PHID-FILE-abc","fields":{}}]},"error_code":null,"error_info":null}"#,
        ])
        let client = PhabricatorClient(
            baseURL: URL(string: "https://phabricator.example.com")!,
            authentication: .apiToken("api-test"),
            transport: transport
        )
        let payload = Data([0x89, 0x50, 0x4E, 0x47])

        let file = try await client.uploadFile(data: payload, name: "shot.png")

        XCTAssertEqual(file, UploadedFile(id: 4321, phid: "PHID-FILE-abc"))
        XCTAssertEqual(file.monogram, "F4321")

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/file.upload", "/api/file.search"])
        let uploadParams = try Self.params(of: requests[0])
        XCTAssertEqual(uploadParams["data_base64"] as? String, payload.base64EncodedString())
        XCTAssertEqual(uploadParams["name"] as? String, "shot.png")
        let searchParams = try Self.params(of: requests[1])
        let constraints = try XCTUnwrap(searchParams["constraints"] as? [String: Any])
        XCTAssertEqual(constraints["phids"] as? [String], ["PHID-FILE-abc"])
    }

    func testUploadFileSurfacesConduitError() async throws {
        let transport = SequencedTransport(responses: [
            #"{"result":null,"error_code":"ERR-CONDUIT-CORE","error_info":"Too large"}"#,
        ])
        let client = PhabricatorClient(
            baseURL: URL(string: "https://phabricator.example.com")!,
            authentication: .apiToken("api-test"),
            transport: transport
        )

        do {
            _ = try await client.uploadFile(data: Data([1]), name: "a.png")
            XCTFail("Expected a Conduit error")
        } catch PhabricatorError.api(let code, let info) {
            XCTAssertEqual(code, "ERR-CONDUIT-CORE")
            XCTAssertEqual(info, "Too large")
        }
    }

    private static func params(of request: URLRequest) throws -> [String: Any] {
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let pairs = body.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1) }
        let raw = try XCTUnwrap(pairs.first { $0.first == "params" }?.last)
        let json = try XCTUnwrap(String(raw).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}

private actor SequencedTransport: Transport {
    private(set) var requests: [URLRequest] = []
    private var responses: [String]

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = responses.isEmpty ? "{}" : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
