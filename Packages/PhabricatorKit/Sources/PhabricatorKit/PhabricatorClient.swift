import Foundation

public actor PhabricatorClient {
    public let baseURL: URL
    public private(set) var authentication: PhabricatorAuthentication

    let transport: Transport
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    public init(
        baseURL: URL,
        authentication: PhabricatorAuthentication = .none,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.transport = URLSessionTransport(session: session)
        self.decoder = Self.makeDecoder()
        self.encoder = Self.makeEncoder()
    }

    init(
        baseURL: URL,
        authentication: PhabricatorAuthentication,
        transport: Transport
    ) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.transport = transport
        self.decoder = Self.makeDecoder()
        self.encoder = Self.makeEncoder()
    }

    public func setAuthentication(_ authentication: PhabricatorAuthentication) {
        self.authentication = authentication
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let seconds = try container.decode(TimeInterval.self)
            return Date(timeIntervalSince1970: seconds)
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension PhabricatorClient {
    func call<P: Encodable, T: Decodable>(method: String, params: P, as type: T.Type = T.self) async throws -> T {
        let paramsData = try encoder.encode(params)
        guard let paramsJSON = String(data: paramsData, encoding: .utf8) else {
            throw PhabricatorError.invalidResponse
        }
        let body = ConduitFormBody.encode(token: authentication.token, paramsJSON: paramsJSON)
        let endpoint = ConduitEndpoint(method: method, body: body)
        let request = try endpoint.request(relativeTo: baseURL)
        let (data, response) = try await transport.send(request)
        try mapStatus(response)
        let envelope: ConduitEnvelope<T>
        do {
            envelope = try decoder.decode(ConduitEnvelope<T>.self, from: data)
        } catch {
            throw PhabricatorError.decoding("\(error)")
        }
        if let code = envelope.errorCode {
            if code == "ERR-INVALID-AUTH" || code == "ERR-INVALID-SESSION" {
                throw PhabricatorError.unauthorized
            }
            throw PhabricatorError.api(code: code, info: envelope.errorInfo ?? code)
        }
        guard let result = envelope.result else {
            throw PhabricatorError.invalidResponse
        }
        return result
    }

    private func mapStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw PhabricatorError.unauthorized
        default:
            throw PhabricatorError.invalidResponse
        }
    }
}

public extension PhabricatorClient {
    func whoami() async throws -> PhabricatorUser {
        struct EmptyParams: Encodable {}
        return try await call(method: "user.whoami", params: EmptyParams())
    }

    func searchRevisions(_ query: RevisionQuery) async throws -> RevisionSearchResult {
        try await call(method: "differential.revision.search", params: query)
    }
}
