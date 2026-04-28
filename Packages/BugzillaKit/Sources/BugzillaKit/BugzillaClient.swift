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

    func searchUsers(match: String, limit: Int = 20) async throws -> [User] {
        let trimmed = match.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        struct Response: Decodable { let users: [User] }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "match", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        query.append(URLQueryItem(
            name: "include_fields",
            value: "id,name,real_name,nick,email"
        ))
        let response: Response = try await execute(Endpoint(path: "user", query: query))
        return response.users
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
        struct Response: Decodable { let bugs: [Bug] }
        let endpoint = Endpoint(
            path: "bug/\(id)",
            query: [URLQueryItem(name: "include_fields", value: "_default,attachments")]
        )
        let response: Response = try await execute(endpoint)
        guard let bug = response.bugs.first else {
            throw BugzillaError.notFound
        }
        return bug
    }

    func getBugs(ids: [Bug.ID]) async throws -> [Bug] {
        struct Response: Decodable { let bugs: [Bug] }
        let endpoint = Endpoint(
            path: "bug",
            query: .repeating("id", values: ids.map(String.init))
        )
        let response: Response = try await execute(endpoint)
        return response.bugs
    }

    func searchBugs(_ query: BugQuery) async throws -> BugSearchResult {
        let endpoint = Endpoint(path: "bug", query: query.queryItems())
        return try await execute(endpoint)
    }

    func updateBug(id: Bug.ID, _ update: BugUpdate) async throws -> [BugChangeResult] {
        struct CommentBody: Encodable {
            let body: String
            let isPrivate: Bool?
        }
        struct Body: Encodable {
            let status: String?
            let resolution: String?
            let dupeOf: Bug.ID?
            let assignedTo: String?
            let priority: String?
            let severity: String?
            let comment: CommentBody?
            let blocks: BugRelationUpdate?
            let dependsOn: BugRelationUpdate?

            enum CodingKeys: String, CodingKey {
                case status, resolution, dupeOf
                case assignedTo, priority, severity, comment
                case blocks, dependsOn
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(status, forKey: .status)
                try c.encodeIfPresent(resolution, forKey: .resolution)
                try c.encodeIfPresent(dupeOf, forKey: .dupeOf)
                try c.encodeIfPresent(assignedTo, forKey: .assignedTo)
                try c.encodeIfPresent(priority, forKey: .priority)
                try c.encodeIfPresent(severity, forKey: .severity)
                try c.encodeIfPresent(comment, forKey: .comment)
                try c.encodeIfPresent(blocks, forKey: .blocks)
                try c.encodeIfPresent(dependsOn, forKey: .dependsOn)
            }
        }

        let payload = Body(
            status: update.status,
            resolution: update.resolution,
            dupeOf: update.dupeOf,
            assignedTo: update.assignedTo,
            priority: update.priority,
            severity: update.severity,
            comment: update.comment.map { CommentBody(body: $0, isPrivate: update.commentIsPrivate) },
            blocks: update.blocks,
            dependsOn: update.dependsOn
        )
        let body = try encoder.encode(payload)

        struct Response: Decodable { let bugs: [BugChangeResult] }
        let endpoint = Endpoint(
            path: "bug/\(id)",
            method: .put,
            body: body
        )
        let response: Response = try await execute(endpoint)
        return response.bugs
    }

    func createBug(_ create: BugCreate) async throws -> Bug.ID {
        struct Body: Encodable {
            let product: String
            let component: String
            let summary: String
            let version: String
            let description: String?
            let type: String?
            let severity: String?
            let priority: String?
            let assignedTo: String?
            let keywords: [String]?
            let whiteboard: String?
            let blocks: [Int]?
            let dependsOn: [Int]?
            let cc: [String]?

            enum CodingKeys: String, CodingKey {
                case product, component, summary, version, description, type
                case severity, priority, assignedTo, keywords, whiteboard, blocks, dependsOn, cc
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(product, forKey: .product)
                try c.encode(component, forKey: .component)
                try c.encode(summary, forKey: .summary)
                try c.encode(version, forKey: .version)
                try c.encodeIfPresent(description, forKey: .description)
                try c.encodeIfPresent(type, forKey: .type)
                try c.encodeIfPresent(severity, forKey: .severity)
                try c.encodeIfPresent(priority, forKey: .priority)
                try c.encodeIfPresent(assignedTo, forKey: .assignedTo)
                try c.encodeIfPresent(keywords, forKey: .keywords)
                try c.encodeIfPresent(whiteboard, forKey: .whiteboard)
                try c.encodeIfPresent(blocks, forKey: .blocks)
                try c.encodeIfPresent(dependsOn, forKey: .dependsOn)
                try c.encodeIfPresent(cc, forKey: .cc)
            }
        }

        let payload = Body(
            product: create.product,
            component: create.component,
            summary: create.summary,
            version: create.version,
            description: create.description,
            type: create.type,
            severity: create.severity,
            priority: create.priority,
            assignedTo: create.assignedTo,
            keywords: create.keywords.isEmpty ? nil : create.keywords,
            whiteboard: create.whiteboard,
            blocks: create.blocks.isEmpty ? nil : create.blocks,
            dependsOn: create.dependsOn.isEmpty ? nil : create.dependsOn,
            cc: create.cc.isEmpty ? nil : create.cc
        )
        let body = try encoder.encode(payload)

        struct Response: Decodable { let id: Bug.ID }
        let endpoint = Endpoint(
            path: "bug",
            method: .post,
            body: body
        )
        let response: Response = try await execute(endpoint)
        return response.id
    }

    func comments(bugID: Bug.ID) async throws -> [Comment] {
        struct Response: Decodable { let bugs: [String: BugComments] }
        struct BugComments: Decodable { let comments: [Comment] }
        let endpoint = Endpoint(path: "bug/\(bugID)/comment")
        let response: Response = try await execute(endpoint)
        return response.bugs[String(bugID)]?.comments ?? []
    }

    func addComment(
        bugID: Bug.ID,
        text: String,
        isPrivate: Bool = false,
        isMarkdown: Bool = false
    ) async throws -> Comment.ID {
        struct Body: Encodable {
            let comment: String
            let isPrivate: Bool
            let isMarkdown: Bool
        }
        struct Response: Decodable { let id: Int }
        let body = try encoder.encode(Body(comment: text, isPrivate: isPrivate, isMarkdown: isMarkdown))
        let endpoint = Endpoint(
            path: "bug/\(bugID)/comment",
            method: .post,
            body: body
        )
        let response: Response = try await execute(endpoint)
        return response.id
    }

    func history(bugID: Bug.ID) async throws -> [HistoryEntry] {
        throw BugzillaError.notImplemented
    }

    func attachments(bugID: Bug.ID) async throws -> [Attachment] {
        throw BugzillaError.notImplemented
    }
}
