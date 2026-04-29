import Foundation

public struct Diff: Decodable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let phid: String
    public let fields: Fields

    public struct Fields: Decodable, Sendable, Hashable {
        public let revisionPHID: String?
        public let authorPHID: String?
        public let repositoryPHID: String?
        public let dateCreated: Date
        public let dateModified: Date
        public let refs: [Ref]?

        public struct Ref: Decodable, Sendable, Hashable {
            public let type: String
            public let name: String?
            public let identifier: String?
            public let commit: String?

            enum CodingKeys: String, CodingKey {
                case type, name, identifier, commit
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.type = try c.decode(String.self, forKey: .type)
                self.name = try c.decodeIfPresent(String.self, forKey: .name)
                self.identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
                self.commit = try c.decodeIfPresent(String.self, forKey: .commit)
            }
        }
    }

    public var baseCommit: String? {
        fields.refs?.first(where: { $0.type == "base" })?.identifier
            ?? fields.refs?.first(where: { $0.type == "base" })?.commit
    }

    public var branch: String? {
        fields.refs?.first(where: { $0.type == "branch" })?.name
    }
}

public struct DiffSearchResult: Decodable, Sendable {
    public let data: [Diff]
    public let cursor: Cursor

    public struct Cursor: Decodable, Sendable {
        public let limit: Int?
        public let after: String?
        public let before: String?
    }
}
