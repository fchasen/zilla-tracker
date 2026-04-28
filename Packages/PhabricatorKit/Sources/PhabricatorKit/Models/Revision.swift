import Foundation

public struct Revision: Decodable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let phid: String
    public let fields: Fields

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

        enum CodingKeys: String, CodingKey {
            case title, uri, authorPHID, status, summary, isDraft
            case dateCreated, dateModified
            case bugzillaBugID = "bugzilla.bug-id"
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
