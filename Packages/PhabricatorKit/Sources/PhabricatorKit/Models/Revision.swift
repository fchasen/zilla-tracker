import Foundation

public struct Revision: Decodable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let phid: String
    public let fields: Fields
    public let attachments: Attachments?

    public struct Fields: Decodable, Sendable, Hashable {
        public let title: String
        public let uri: URL?
        public let authorPHID: String
        public let status: RevisionStatus
        public let summary: String?
        public let isDraft: Bool
        public let dateCreated: Date
        public let dateModified: Date
        public let bugzillaBugID: String?
        public let repositoryPHID: String?
        public let diffPHID: String?
        public let policy: Policy?

        public struct Policy: Decodable, Sendable, Hashable {
            public let view: String
            public let edit: String
        }

        enum CodingKeys: String, CodingKey {
            case title, uri, authorPHID, status, summary, isDraft
            case dateCreated, dateModified
            case bugzillaBugID = "bugzilla.bug-id"
            case repositoryPHID
            case diffPHID
            case policy
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try c.decode(String.self, forKey: .title)
            self.uri = try c.decodeIfPresent(URL.self, forKey: .uri)
            self.authorPHID = try c.decode(String.self, forKey: .authorPHID)
            self.status = try c.decode(RevisionStatus.self, forKey: .status)
            self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
            self.isDraft = try c.decode(Bool.self, forKey: .isDraft)
            self.dateCreated = try c.decode(Date.self, forKey: .dateCreated)
            self.dateModified = try c.decode(Date.self, forKey: .dateModified)
            self.bugzillaBugID = try c.decodeIfPresent(String.self, forKey: .bugzillaBugID)
            self.repositoryPHID = try c.decodeIfPresent(String.self, forKey: .repositoryPHID)
            self.diffPHID = try c.decodeIfPresent(String.self, forKey: .diffPHID)
            self.policy = try c.decodeIfPresent(Policy.self, forKey: .policy)
        }

        public var isViewRestricted: Bool {
            guard let view = policy?.view else { return false }
            return view != "public" && view != "users"
        }
    }

    public struct Attachments: Decodable, Sendable, Hashable {
        public let reviewers: ReviewersAttachment?
        public let subscribers: SubscribersAttachment?
        public let projects: ProjectsAttachment?

        public struct ReviewersAttachment: Decodable, Sendable, Hashable {
            public let reviewers: [Reviewer]
        }

        public struct SubscribersAttachment: Decodable, Sendable, Hashable {
            public let subscriberPHIDs: [String]?
            public let subscriberCount: Int?
            public let viewerIsSubscribed: Bool?
        }

        public struct ProjectsAttachment: Decodable, Sendable, Hashable {
            public let projectPHIDs: [String]?
        }

        enum CodingKeys: String, CodingKey {
            case reviewers, subscribers, projects
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.reviewers = try c.decodeIfPresent(ReviewersAttachment.self, forKey: .reviewers)
            self.subscribers = try c.decodeIfPresent(SubscribersAttachment.self, forKey: .subscribers)
            self.projects = try c.decodeIfPresent(ProjectsAttachment.self, forKey: .projects)
        }
    }

    public var revisionLabel: String { "D\(id)" }
}

public struct RevisionSearchResult: Decodable, Sendable {
    public let data: [Revision]
    public let cursor: Cursor

    public struct Cursor: Decodable, Sendable {
        public let limit: Int?
        public let after: String?
        public let before: String?
    }
}
