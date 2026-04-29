import Foundation

public struct ProjectQuery: Sendable, Hashable, Encodable {
    public var queryKey: String?
    public var constraints: Constraints?
    public var order: String?
    public var limit: Int?
    public var before: String?
    public var after: String?

    public init(
        queryKey: String? = nil,
        constraints: Constraints? = nil,
        order: String? = nil,
        limit: Int? = nil,
        before: String? = nil,
        after: String? = nil
    ) {
        self.queryKey = queryKey
        self.constraints = constraints
        self.order = order
        self.limit = limit
        self.before = before
        self.after = after
    }

    public struct Constraints: Sendable, Hashable, Encodable {
        public var ids: [Int]?
        public var phids: [String]?
        public var name: String?
        public var slugs: [String]?
        public var query: String?

        public init(
            ids: [Int]? = nil,
            phids: [String]? = nil,
            name: String? = nil,
            slugs: [String]? = nil,
            query: String? = nil
        ) {
            self.ids = ids
            self.phids = phids
            self.name = name
            self.slugs = slugs
            self.query = query
        }
    }
}

public extension ProjectQuery {
    static func byName(_ fragment: String, limit: Int = 25) -> ProjectQuery {
        ProjectQuery(
            constraints: Constraints(name: fragment),
            limit: limit
        )
    }

    static func byPHIDs(_ phids: [String]) -> ProjectQuery {
        ProjectQuery(
            constraints: Constraints(phids: phids),
            limit: max(phids.count, 1)
        )
    }
}
