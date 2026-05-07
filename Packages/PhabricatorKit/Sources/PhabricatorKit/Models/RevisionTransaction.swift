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
        public let oldPHIDs: [String]?
        public let newPHIDs: [String]?
        public let operations: [Operation]?

        public let diffID: Int?
        public let diffPHID: String?
        public let path: String?
        public let line: Int?
        public let length: Int?
        public let replyToCommentPHID: String?
        public let isNewFile: Bool?
        public let isDone: Bool?

        public struct Operation: Decodable, Sendable, Hashable {
            public let operation: String?
            public let phid: String?
            public let oldStatus: String?
            public let newStatus: String?
            public let isBlocking: Bool?

            public init(operation: String?, phid: String?, oldStatus: String?, newStatus: String?, isBlocking: Bool?) {
                self.operation = operation
                self.phid = phid
                self.oldStatus = oldStatus
                self.newStatus = newStatus
                self.isBlocking = isBlocking
            }

            enum CodingKeys: String, CodingKey {
                case operation, phid, oldStatus, newStatus, isBlocking
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.operation = try? c.decodeIfPresent(String.self, forKey: .operation)
                self.phid = try? c.decodeIfPresent(String.self, forKey: .phid)
                self.oldStatus = try? c.decodeIfPresent(String.self, forKey: .oldStatus)
                self.newStatus = try? c.decodeIfPresent(String.self, forKey: .newStatus)
                if let b = try? c.decodeIfPresent(Bool.self, forKey: .isBlocking) {
                    self.isBlocking = b
                } else if let i = try? c.decodeIfPresent(Int.self, forKey: .isBlocking) {
                    self.isBlocking = i != 0
                } else {
                    self.isBlocking = nil
                }
            }
        }

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
            case operations
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
            self.oldPHIDs = try? c.decodeIfPresent([String].self, forKey: .oldValue)
            self.newPHIDs = try? c.decodeIfPresent([String].self, forKey: .newValue)
            self.operations = try? c.decodeIfPresent([Operation].self, forKey: .operations)
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
        self.oldPHIDs = nil
        self.newPHIDs = nil
        self.operations = nil
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

public extension RevisionTransaction {
    /// Structured classification of a transaction's payload — for UI rendering.
    /// Falls back to `.verb` for purely lifecycle-style changes that have no
    /// extra payload, and `.unknown` for transaction types we don't recognize.
    enum Kind: Sendable, Hashable {
        case comment
        case inline
        case titleChange(old: String?, new: String?)
        case summaryChange(old: String?, new: String?)
        case testPlanChange(old: String?, new: String?)
        case statusChange(old: String?, new: String?)
        case bugIDChange(old: String?, new: String?)
        case diffUpdate(diffID: Int?, diffPHID: String?)
        case reviewersChanged(operations: [TransactionFields.Operation])
        case subscribersChanged(adds: [String], removes: [String])
        case projectsChanged(adds: [String], removes: [String])
        case columnsChanged
        case buildStatus(old: String?, new: String?)
        case verb(Verb)
        case unknown(rawType: String?)

        public enum Verb: Sendable, Hashable {
            case accept
            case reject
            case requestChanges
            case abandon
            case reclaim
            case reopen
            case close
            case planChanges
            case requestReview
            case resign
            case create
            case commandeer
            case mfaConfirmed
        }
    }

    var kind: Kind {
        if isComment {
            return (fields.path != nil && fields.line != nil) ? .inline : .comment
        }
        switch type {
        case "title":
            return .titleChange(old: fields.oldValue, new: fields.newValue)
        case "summary":
            return .summaryChange(old: fields.oldValue, new: fields.newValue)
        case "test-plan", "differential.test-plan":
            return .testPlanChange(old: fields.oldValue, new: fields.newValue)
        case "status", "differential:status":
            return .statusChange(old: fields.oldValue, new: fields.newValue)
        case "bugzilla.bug-id":
            return .bugIDChange(old: fields.oldValue, new: fields.newValue)
        case "update", "differential.diff", "differential:diff":
            return .diffUpdate(diffID: fields.diffID, diffPHID: fields.diffPHID)
        case "reviewers.add", "reviewers.remove", "reviewers.set", "reviewers.update", "reviewer", "reviewers":
            return .reviewersChanged(operations: reviewerOperations())
        case "subscribers.add", "subscribers.remove", "subscribers.set", "subscriber":
            let (adds, removes) = subscriberDeltas()
            return .subscribersChanged(adds: adds, removes: removes)
        case "projects.add", "projects.remove", "projects.set":
            let (adds, removes) = projectDeltas()
            return .projectsChanged(adds: adds, removes: removes)
        case "core:columns":
            return .columnsChanged
        case "harbormaster:buildable", "harbormaster:status", "harbormaster:build",
             "harbormaster.buildable.create", "harbormaster.build.status":
            return .buildStatus(old: fields.oldValue, new: fields.newValue)
        case "accept": return .verb(.accept)
        case "reject": return .verb(.reject)
        case "request-changes": return .verb(.requestChanges)
        case "abandon": return .verb(.abandon)
        case "reclaim": return .verb(.reclaim)
        case "reopen": return .verb(.reopen)
        case "close": return .verb(.close)
        case "plan-changes": return .verb(.planChanges)
        case "request-review": return .verb(.requestReview)
        case "resign": return .verb(.resign)
        case "create": return .verb(.create)
        case "commandeer": return .verb(.commandeer)
        case "mfa": return .verb(.mfaConfirmed)
        default:
            if isHarbormasterAuthored || (type?.lowercased().contains("harbormaster") ?? false) {
                return .buildStatus(old: fields.oldValue, new: fields.newValue)
            }
            return .unknown(rawType: type)
        }
    }

    private var isHarbormasterAuthored: Bool {
        authorPHID == "PHID-APPS-PhabricatorHarbormasterApplication"
    }

    private func reviewerOperations() -> [TransactionFields.Operation] {
        if let ops = fields.operations, !ops.isEmpty { return ops }
        // Fallback: synthesize from `new` PHID array when `operations` absent
        // (older Phabricator forks emitted `reviewers.set` with `new: [phid,...]`).
        if let news = fields.newPHIDs {
            let olds = Set(fields.oldPHIDs ?? [])
            let nowSet = Set(news)
            let added = news.filter { !olds.contains($0) }.map {
                TransactionFields.Operation(operation: "add", phid: $0, oldStatus: nil, newStatus: nil, isBlocking: nil)
            }
            let removed = (fields.oldPHIDs ?? []).filter { !nowSet.contains($0) }.map {
                TransactionFields.Operation(operation: "remove", phid: $0, oldStatus: nil, newStatus: nil, isBlocking: nil)
            }
            return added + removed
        }
        return []
    }

    private func subscriberDeltas() -> (adds: [String], removes: [String]) {
        if let ops = fields.operations, !ops.isEmpty {
            let adds = ops.filter { $0.operation == "add" }.compactMap(\.phid)
            let removes = ops.filter { $0.operation == "remove" }.compactMap(\.phid)
            return (adds, removes)
        }
        let olds = Set(fields.oldPHIDs ?? [])
        let news = Set(fields.newPHIDs ?? [])
        return (Array(news.subtracting(olds)), Array(olds.subtracting(news)))
    }

    private func projectDeltas() -> (adds: [String], removes: [String]) {
        if let ops = fields.operations, !ops.isEmpty {
            let adds = ops.filter { $0.operation == "add" }.compactMap(\.phid)
            let removes = ops.filter { $0.operation == "remove" }.compactMap(\.phid)
            return (adds, removes)
        }
        let olds = Set(fields.oldPHIDs ?? [])
        let news = Set(fields.newPHIDs ?? [])
        return (Array(news.subtracting(olds)), Array(olds.subtracting(news)))
    }

    /// PHIDs referenced inside `fields` (operations, old/new PHID arrays).
    /// Use to extend user/project directories so chips can show names.
    var referencedPHIDs: [String] {
        var out: [String] = []
        if let ops = fields.operations {
            for op in ops { if let p = op.phid { out.append(p) } }
        }
        if let arr = fields.oldPHIDs { out.append(contentsOf: arr) }
        if let arr = fields.newPHIDs { out.append(contentsOf: arr) }
        return out
    }
}

/// Friendly names for the system "application" actors that appear as
/// `authorPHID` on automated transactions (Herald rules, Harbormaster builds,
/// Diffusion commits, etc.). These never resolve through `user.search` because
/// they aren't users — they're the apps acting on the revision's behalf.
public enum SystemActor {
    public static func displayName(forPHID phid: String) -> String? {
        guard phid.hasPrefix("PHID-APPS-Phabricator") else { return nil }
        let stripped = phid.replacingOccurrences(of: "PHID-APPS-Phabricator", with: "")
            .replacingOccurrences(of: "Application", with: "")
        return stripped.isEmpty ? nil : stripped
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
