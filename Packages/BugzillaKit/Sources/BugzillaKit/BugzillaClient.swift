import Foundation

public actor BugzillaClient {
    public let baseURL: URL
    public private(set) var authentication: Authentication

    let transport: Transport
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    public init(
        baseURL: URL,
        authentication: Authentication = .none,
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
        authentication: Authentication,
        transport: Transport
    ) {
        self.baseURL = baseURL
        self.authentication = authentication
        self.transport = transport
        self.decoder = Self.makeDecoder()
        self.encoder = Self.makeEncoder()
    }

    public func setAuthentication(_ authentication: Authentication) {
        self.authentication = authentication
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .formatted(dateFormatter)
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .formatted(dateFormatter)
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}

extension BugzillaClient {
    func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard let url = endpoint.url(relativeTo: baseURL) else {
            throw BugzillaError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        authentication.apply(to: &request)
        return request
    }

    func execute<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let request = try makeRequest(for: endpoint)
        let (data, response) = try await transport.send(request)
        try mapStatus(response, data: data)
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data), envelope.error {
            throw BugzillaError.api(code: envelope.code, message: envelope.message)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BugzillaError.decoding("\(error)")
        }
    }

    private func mapStatus(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw BugzillaError.unauthorized
        case 404:
            throw BugzillaError.notFound
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw BugzillaError.rateLimited(retryAfter: retryAfter)
        default:
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw BugzillaError.api(code: envelope.code, message: envelope.message)
            }
            throw BugzillaError.invalidResponse
        }
    }
}

public extension BugzillaClient {
    func version() async throws -> String {
        struct Response: Decodable { let version: String }
        let response: Response = try await execute(Endpoint(path: "version"))
        return response.version
    }

    func login(name: String, apiKey: String, restrictToIP: Bool = true) async throws -> Authentication {
        struct Response: Decodable {
            let id: Int
            let token: String
        }
        let endpoint = Endpoint(
            path: "login",
            query: [
                URLQueryItem(name: "login", value: name),
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "restrict_login", value: restrictToIP ? "true" : "false")
            ]
        )
        let response: Response = try await execute(endpoint)
        let auth = Authentication.token(response.token, userID: response.id)
        self.authentication = auth
        return auth
    }

    func validLogin() async throws -> Bool {
        do {
            _ = try await whoami()
            return true
        } catch BugzillaError.unauthorized {
            return false
        }
    }

    func logout() async throws {
        struct Empty: Decodable {}
        let _: Empty = try await execute(Endpoint(path: "logout"))
        self.authentication = .none
    }

    func whoami() async throws -> User {
        try await execute(Endpoint(path: "whoami"))
    }

    func selectableProducts() async throws -> [Product] {
        struct IDList: Decodable { let ids: [Int] }
        let idResponse: IDList = try await execute(Endpoint(path: "product_selectable"))
        if idResponse.ids.isEmpty { return [] }
        return try await products(ids: idResponse.ids)
    }

    func products(ids: [Int]) async throws -> [Product] {
        try await fetchProducts(query:
            .repeating("ids", values: ids.map(String.init))
            + [Self.productIncludeFieldsItem]
        )
    }

    func products(names: [String]) async throws -> [Product] {
        try await fetchProducts(query:
            .repeating("names", values: names)
            + [Self.productIncludeFieldsItem]
        )
    }

    private func fetchProducts(query: [URLQueryItem]) async throws -> [Product] {
        struct Response: Decodable { let products: [Product] }
        let endpoint = Endpoint(path: "product", query: query)
        let response: Response = try await execute(endpoint)
        return response.products
    }

    private static let productIncludeFieldsItem = URLQueryItem(
        name: "include_fields",
        value: [
            "id", "name", "description", "is_active",
            "components.id", "components.name", "components.description",
            "components.default_assigned_to", "components.is_active"
        ].joined(separator: ",")
    )

    func getBug(id: Bug.ID) async throws -> Bug {
        throw BugzillaError.notImplemented
    }

    func getBugs(ids: [Bug.ID]) async throws -> [Bug] {
        throw BugzillaError.notImplemented
    }

    func searchBugs(_ query: BugQuery) async throws -> BugSearchResult {
        throw BugzillaError.notImplemented
    }

    func comments(bugID: Bug.ID) async throws -> [Comment] {
        throw BugzillaError.notImplemented
    }

    func history(bugID: Bug.ID) async throws -> [HistoryEntry] {
        throw BugzillaError.notImplemented
    }

    func attachments(bugID: Bug.ID) async throws -> [Attachment] {
        throw BugzillaError.notImplemented
    }
}
