import XCTest
@testable import BugzillaKit

final class AttachmentTests: XCTestCase {
    let baseURL = URL(string: "https://bugzilla.example.com")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testCreateAttachmentSendsBase64Payload() async throws {
        let payload = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/bug/1234567/attachment")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["ids"] as? [Int], [1234567])
            XCTAssertEqual(json["data"] as? String, payload.base64EncodedString())
            XCTAssertEqual(json["file_name"] as? String, "screenshot.png")
            XCTAssertEqual(json["summary"] as? String, "Screenshot")
            XCTAssertEqual(json["content_type"] as? String, "image/png")
            XCTAssertEqual(json["is_markdown"] as? Bool, true)
            XCTAssertNil(json["comment"])

            return (httpResponse(for: request, status: 201), #"{"ids":["2797"]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let id = try await client.createAttachment(
            bugID: 1234567,
            data: payload,
            fileName: "screenshot.png",
            summary: "Screenshot",
            contentType: "image/png"
        )
        XCTAssertEqual(id, 2797)
    }

    func testCreateAttachmentSendsComment() async throws {
        MockURLProtocol.handler = { request in
            let body = request.bodyData ?? Data()
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["comment"] as? String, "See the screenshot")
            return (httpResponse(for: request, status: 201), #"{"ids":[12]}"#.data(using: .utf8)!)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let id = try await client.createAttachment(
            bugID: 1,
            data: Data([1]),
            fileName: "a.png",
            summary: "a.png",
            contentType: "image/png",
            comment: "See the screenshot"
        )
        XCTAssertEqual(id, 12)
    }

    func testCreateAttachmentDecodesAttachmentsMap() async throws {
        MockURLProtocol.handler = { request in
            let responseBody = #"""
            {"attachments":{"9876":{"id":9876,"file_name":"a.png","content_type":"image/png"}}}
            """#.data(using: .utf8)!
            return (httpResponse(for: request, status: 201), responseBody)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        let id = try await client.createAttachment(
            bugID: 1,
            data: Data([1]),
            fileName: "a.png",
            summary: "a.png",
            contentType: "image/png"
        )
        XCTAssertEqual(id, 9876)
    }

    func testCreateAttachmentSurfacesAPIError() async throws {
        MockURLProtocol.handler = { request in
            let responseBody = #"{"error":true,"code":600,"message":"Attachment too large"}"#.data(using: .utf8)!
            return (httpResponse(for: request, status: 400), responseBody)
        }

        let client = BugzillaClient(baseURL: baseURL, session: MockURLProtocol.session())
        do {
            _ = try await client.createAttachment(
                bugID: 1,
                data: Data([1]),
                fileName: "a.png",
                summary: "a.png",
                contentType: "image/png"
            )
            XCTFail("Expected an API error")
        } catch let BugzillaError.api(code, message) {
            XCTAssertEqual(code, 600)
            XCTAssertEqual(message, "Attachment too large")
        }
    }
}

private extension URLRequest {
    var bodyData: Data? {
        if let direct = httpBody {
            return direct
        }
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
