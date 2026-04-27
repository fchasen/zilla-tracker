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

public extension BugzillaClient {
    func version() async throws -> String {
        throw BugzillaError.notImplemented
    }

    func login(name: String, apiKey: String, restrictToIP: Bool = true) async throws -> Authentication {
        throw BugzillaError.notImplemented
    }

    func validLogin(_ authentication: Authentication) async throws -> Bool {
        throw BugzillaError.notImplemented
    }

    func logout() async throws {
        throw BugzillaError.notImplemented
    }

    func whoami() async throws -> User {
        throw BugzillaError.notImplemented
    }

    func selectableProducts() async throws -> [Product] {
        throw BugzillaError.notImplemented
    }

    func products(ids: [Int]) async throws -> [Product] {
        throw BugzillaError.notImplemented
    }

    func products(names: [String]) async throws -> [Product] {
        throw BugzillaError.notImplemented
    }

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
