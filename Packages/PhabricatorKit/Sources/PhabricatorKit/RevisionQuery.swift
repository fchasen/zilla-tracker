import Foundation

public struct RevisionQuery: Sendable, Hashable, Encodable {
    public var queryKey: String?
    public var constraints: Constraints?
    public var attachments: Attachments?
    public var order: String?
    public var limit: Int?
    public var before: String?
    public var after: String?

    public init(
        queryKey: String? = nil,
        constraints: Constraints? = nil,
        attachments: Attachments? = nil,
        order: String? = nil,
        limit: Int? = nil,
        before: String? = nil,
        after: String? = nil
    ) {
        self.queryKey = queryKey
        self.constraints = constraints
        self.attachments = attachments
        self.order = order
        self.limit = limit
        self.before = before
        self.after = after
    }

    public struct Constraints: Sendable, Hashable, Encodable {
        public var ids: [Int]?
        public var phids: [String]?
        public var authorPHIDs: [String]?
        public var reviewerPHIDs: [String]?
        public var responsiblePHIDs: [String]?
        public var statuses: [String]?
        public var query: String?
        public var modifiedStart: Int?
        public var modifiedEnd: Int?

        public init(
            ids: [Int]? = nil,
            phids: [String]? = nil,
            authorPHIDs: [String]? = nil,
            reviewerPHIDs: [String]? = nil,
            responsiblePHIDs: [String]? = nil,
            statuses: [String]? = nil,
            query: String? = nil,
            modifiedStart: Int? = nil,
            modifiedEnd: Int? = nil
        ) {
            self.ids = ids
            self.phids = phids
            self.authorPHIDs = authorPHIDs
            self.reviewerPHIDs = reviewerPHIDs
            self.responsiblePHIDs = responsiblePHIDs
            self.statuses = statuses
            self.query = query
            self.modifiedStart = modifiedStart
            self.modifiedEnd = modifiedEnd
        }
    }

    public struct Attachments: Sendable, Hashable, Encodable {
        public var reviewers: Bool?
        public var reviewersExtra: Bool?
        public var subscribers: Bool?
        public var projects: Bool?

        public init(reviewers: Bool? = nil, reviewersExtra: Bool? = nil, subscribers: Bool? = nil, projects: Bool? = nil) {
            self.reviewers = reviewers
            self.reviewersExtra = reviewersExtra
            self.subscribers = subscribers
            self.projects = projects
        }

        enum CodingKeys: String, CodingKey {
            case reviewers
            case reviewersExtra = "reviewers-extra"
            case subscribers
            case projects
        }
    }
}

public extension RevisionQuery {
    static func active(authorPHID: String, statuses: [String]? = nil) -> RevisionQuery {
        RevisionQuery(
            constraints: Constraints(
                authorPHIDs: [authorPHID],
                statuses: statuses ?? RevisionStatus.Value.openValues
            ),
            order: "updated"
        )
    }

    static func reviewing(responsiblePHID: String, statuses: [String]? = nil) -> RevisionQuery {
        RevisionQuery(
            constraints: Constraints(
                responsiblePHIDs: [responsiblePHID],
                statuses: statuses ?? [RevisionStatus.Value.needsReview]
            ),
            attachments: Attachments(reviewers: true),
            order: "updated"
        )
    }

    static func landed(authorPHID: String, since: Date) -> RevisionQuery {
        RevisionQuery(
            constraints: Constraints(
                authorPHIDs: [authorPHID],
                statuses: [RevisionStatus.Value.published],
                modifiedStart: Int(since.timeIntervalSince1970)
            ),
            order: "updated"
        )
    }
}
