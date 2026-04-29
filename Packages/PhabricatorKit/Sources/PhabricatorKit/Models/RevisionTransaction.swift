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

        enum CodingKeys: String, CodingKey {
            case id, phid, version, authorPHID, dateCreated, dateModified, removed, content
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let i = try? c.decode(Int.self, forKey: .id) { self.id = i }
            else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) { self.id = i }
            else { self.id = 0 }
            self.phid = try c.decode(String.self, forKey: .phid)
            self.version = try? c.decodeIfPresent(Int.self, forKey: .version)
            self.authorPHID = try c.decodeIfPresent(String.self, forKey: .authorPHID)
            self.dateCreated = try c.decode(Date.self, forKey: .dateCreated)
            self.dateModified = try c.decode(Date.self, forKey: .dateModified)
            if let b = try? c.decodeIfPresent(Bool.self, forKey: .removed) {
                self.removed = b
            } else if let i = try? c.decodeIfPresent(Int.self, forKey: .removed) {
                self.removed = i != 0
            } else {
                self.removed = nil
            }
            self.content = (try? c.decode(Content.self, forKey: .content)) ?? Content(raw: nil)
        }
    }

    public struct TransactionFields: Decodable, Sendable, Hashable {
        public let oldValue: String?
        public let newValue: String?

        public let diffID: Int?
        public let diffPHID: String?
        public let path: String?
        public let line: Int?
        public let length: Int?
        public let replyToCommentPHID: String?
        public let isNewFile: Bool?
        public let isDone: Bool?

        enum CodingKeys: String, CodingKey {
            case oldValue = "old"
            case newValue = "new"
            case diff
            case path
            case line
            case length
            case replyToCommentPHID
            case isNewFile
            case isDone
        }

        struct DiffKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { Int(stringValue) }
            init?(intValue: Int) { self.stringValue = String(intValue) }
            static let id = DiffKeys(stringValue: "id")!
            static let phid = DiffKeys(stringValue: "phid")!
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.oldValue = Self.decodeStringish(c, key: .oldValue)
            self.newValue = Self.decodeStringish(c, key: .newValue)
            // `diff` may arrive as a nested object {id, phid}, as a bare int,
            // or as a numeric string. Try each shape.
            if let diffContainer = try? c.nestedContainer(keyedBy: DiffKeys.self, forKey: .diff) {
                self.diffID = Self.decodeFlexibleInt(diffContainer, key: .id)
                self.diffPHID = try? diffContainer.decodeIfPresent(String.self, forKey: .phid)
            } else if let i = try? c.decodeIfPresent(Int.self, forKey: .diff) {
                self.diffID = i
                self.diffPHID = nil
            } else if let s = try? c.decodeIfPresent(String.self, forKey: .diff), let i = Int(s) {
                self.diffID = i
                self.diffPHID = nil
            } else {
                self.diffID = nil
                self.diffPHID = nil
            }
            self.path = try? c.decodeIfPresent(String.self, forKey: .path)
            self.line = Self.decodeFlexibleInt(c, key: .line)
            self.length = Self.decodeFlexibleInt(c, key: .length)
            self.replyToCommentPHID = try? c.decodeIfPresent(String.self, forKey: .replyToCommentPHID)
            self.isNewFile = Self.decodeFlexibleBool(c, key: .isNewFile)
            self.isDone = Self.decodeFlexibleBool(c, key: .isDone)
        }

        private static func decodeStringish(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
            if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return String(d) }
            if let b = try? c.decodeIfPresent(Bool.self, forKey: key) { return String(b) }
            return nil
        }

        private static func decodeFlexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
            if let s = try? c.decodeIfPresent(String.self, forKey: key), let i = Int(s) { return i }
            return nil
        }

        private static func decodeFlexibleInt(_ c: KeyedDecodingContainer<DiffKeys>, key: DiffKeys) -> Int? {
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
            if let s = try? c.decodeIfPresent(String.self, forKey: key), let i = Int(s) { return i }
            return nil
        }

        private static func decodeFlexibleBool(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool? {
            if let b = try? c.decodeIfPresent(Bool.self, forKey: key) { return b }
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s == "1" || s.lowercased() == "true" }
            return nil
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
        self.diffID = nil
        self.diffPHID = nil
        self.path = nil
        self.line = nil
        self.length = nil
        self.replyToCommentPHID = nil
        self.isNewFile = nil
        self.isDone = nil
    }
}

public extension RevisionTransaction {
    /// Whether this transaction represents a user-authored comment — either a
    /// top-level comment on the revision or an inline comment on a diff line.
    /// Other transaction types (status changes, reviewer changes, rebases,
    /// etc.) are activity but not comments.
    var isComment: Bool {
        if type == "comment" || type == "inline" { return true }
        // Some Phabricator forks emit `differential.inline` / `differential:inline`.
        if let type, type.hasSuffix("inline") || type.hasSuffix(":inline") { return true }
        // Inline comments always carry a path + line anchor; a fallback check
        // catches transaction-type strings we haven't seen.
        if fields.path != nil && fields.line != nil { return true }
        // A non-empty top-level comment body without an anchor is also a comment.
        if let body = comments.last(where: { ($0.removed ?? false) == false })?.content.raw,
           !body.isEmpty {
            // Only treat as a comment if the type is missing or hints at one;
            // status changes etc. don't carry comment bodies.
            return type == nil || type == "comment"
        }
        return false
    }

    /// Builds an `InlineComment` from an inline-typed transaction.
    /// Inline transactions are recognized by their anchor fields (`diff`,
    /// `path`, `line`) rather than a specific `type` string, since different
    /// Phabricator forks emit different names (`inline`, `differential.inline`,
    /// `differential:inline`).
    /// Drafts are not exposed via `transaction.search`; only published inlines.
    func inlineComment() -> InlineComment? {
        guard let diffID = fields.diffID,
              let path = fields.path, !path.isEmpty,
              let line = fields.line else {
            return nil
        }
        guard let body = comments.last(where: { ($0.removed ?? false) == false })?.content.raw,
              !body.isEmpty else {
            return nil
        }
        return InlineComment(
            id: id,
            phid: comments.last(where: { ($0.removed ?? false) == false })?.phid ?? phid,
            authorPHID: authorPHID,
            diffID: diffID,
            path: path,
            line: line,
            length: max(1, (fields.length ?? 0) + 1),
            isNewFile: fields.isNewFile ?? true,
            isDeleted: false,
            replyToCommentPHID: fields.replyToCommentPHID,
            transactionPHID: phid,
            content: body,
            dateCreated: dateCreated,
            dateModified: dateModified
        )
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
