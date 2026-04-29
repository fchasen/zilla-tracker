import Foundation

public struct DiffQuery: Sendable, Hashable, Encodable {
    public var constraints: Constraints?
    public var order: String?
    public var limit: Int?
    public var before: String?
    public var after: String?

    public init(
        constraints: Constraints? = nil,
        order: String? = nil,
        limit: Int? = nil,
        before: String? = nil,
        after: String? = nil
    ) {
        self.constraints = constraints
        self.order = order
        self.limit = limit
        self.before = before
        self.after = after
    }

    public struct Constraints: Sendable, Hashable, Encodable {
        public var ids: [Int]?
        public var phids: [String]?
        public var revisionPHIDs: [String]?

        public init(ids: [Int]? = nil, phids: [String]? = nil, revisionPHIDs: [String]? = nil) {
            self.ids = ids
            self.phids = phids
            self.revisionPHIDs = revisionPHIDs
        }
    }
}

public extension DiffQuery {
    static func forRevision(_ revisionPHID: String, limit: Int = 50) -> DiffQuery {
        DiffQuery(
            constraints: Constraints(revisionPHIDs: [revisionPHID]),
            order: "newest",
            limit: limit
        )
    }
}
