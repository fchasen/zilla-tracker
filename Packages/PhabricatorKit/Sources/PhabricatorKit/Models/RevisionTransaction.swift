import Foundation

public struct RevisionTransaction: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let phid: String
    public let type: String?
    public let authorPHID: String?
    public let objectPHID: String?
    public let dateCreated: Date
    public let dateModified: Date
    public let comments: [Comment]
    public let fields: TransactionFields

    public struct Comment: Decodable, Sendable, Hashable, Identifiable {
        public let id: Int
        public let phid: String
        public let version: Int?
        public let authorPHID: String?
        public let dateCreated: Date
        public let dateModified: Date
        public let removed: Bool?
        public let content: Content

        public struct Content: Decodable, Sendable, Hashable {
            public let raw: String?
        }
    }

    public struct TransactionFields: Decodable, Sendable, Hashable {
        public let oldValue: String?
        public let newValue: String?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicKeys.self)
            self.oldValue = (try? c.decodeIfPresent(String.self, forKey: .init(stringValue: "old")!)) ?? nil
            self.newValue = (try? c.decodeIfPresent(String.self, forKey: .init(stringValue: "new")!)) ?? nil
        }

        struct DynamicKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, phid, type, authorPHID, objectPHID
        case dateCreated, dateModified, comments, fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { self.id = i }
        else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) { self.id = i }
        else { self.id = 0 }
        self.phid = try c.decode(String.self, forKey: .phid)
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.authorPHID = try c.decodeIfPresent(String.self, forKey: .authorPHID)
        self.objectPHID = try c.decodeIfPresent(String.self, forKey: .objectPHID)
        self.dateCreated = try c.decode(Date.self, forKey: .dateCreated)
        self.dateModified = try c.decode(Date.self, forKey: .dateModified)
        self.comments = try c.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        self.fields = (try? c.decode(TransactionFields.self, forKey: .fields))
            ?? TransactionFields(empty: ())
    }
}

extension RevisionTransaction.TransactionFields {
    init(empty: Void) {
        self.oldValue = nil
        self.newValue = nil
    }
}

public struct TransactionSearchResult: Decodable, Sendable {
    public let data: [RevisionTransaction]
    public let cursor: Cursor

    public struct Cursor: Decodable, Sendable {
        public let limit: Int?
        public let after: String?
        public let before: String?
    }
}
