import Foundation

public struct InlineComment: Sendable, Hashable, Identifiable {
    public let id: Int
    public let phid: String
    public let authorPHID: String?
    public let diffID: Int
    public let path: String
    public let line: Int
    public let length: Int
    public let isNewFile: Bool
    public let isDeleted: Bool
    public let replyToCommentPHID: String?
    public let transactionPHID: String?
    public let content: String
    public let dateCreated: Date?
    public let dateModified: Date?

    public init(
        id: Int,
        phid: String,
        authorPHID: String?,
        diffID: Int,
        path: String,
        line: Int,
        length: Int,
        isNewFile: Bool,
        isDeleted: Bool,
        replyToCommentPHID: String?,
        transactionPHID: String?,
        content: String,
        dateCreated: Date?,
        dateModified: Date?
    ) {
        self.id = id
        self.phid = phid
        self.authorPHID = authorPHID
        self.diffID = diffID
        self.path = path
        self.line = line
        self.length = length
        self.isNewFile = isNewFile
        self.isDeleted = isDeleted
        self.replyToCommentPHID = replyToCommentPHID
        self.transactionPHID = transactionPHID
        self.content = content
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }

    public var isDraft: Bool { transactionPHID == nil }
}

struct DifferentialGetInlinesRaw: Decodable, Sendable {
    let id: Int
    let phid: String
    let authorPHID: String?
    let diffID: Int
    let filePath: String
    let lineNumber: Int
    let lineLength: Int
    let isNewFile: Bool
    let isDeleted: Bool?
    let replyToCommentPHID: String?
    let transactionPHID: String?
    let content: String
    let dateCreated: Date?
    let dateModified: Date?

    enum CodingKeys: String, CodingKey {
        case id, phid, authorPHID, diffID, filePath, lineNumber, lineLength, isNewFile, isDeleted
        case replyToCommentPHID, transactionPHID, content, dateCreated, dateModified
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try Self.flexibleInt(c, key: .id) ?? 0
        self.phid = try c.decode(String.self, forKey: .phid)
        self.authorPHID = try c.decodeIfPresent(String.self, forKey: .authorPHID)
        self.diffID = try Self.flexibleInt(c, key: .diffID) ?? 0
        self.filePath = try c.decodeIfPresent(String.self, forKey: .filePath) ?? ""
        self.lineNumber = try Self.flexibleInt(c, key: .lineNumber) ?? 0
        self.lineLength = try Self.flexibleInt(c, key: .lineLength) ?? 1
        self.isNewFile = try Self.flexibleBool(c, key: .isNewFile) ?? false
        self.isDeleted = try Self.flexibleBool(c, key: .isDeleted)
        self.replyToCommentPHID = try c.decodeIfPresent(String.self, forKey: .replyToCommentPHID)
        self.transactionPHID = try c.decodeIfPresent(String.self, forKey: .transactionPHID)
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.dateCreated = try? c.decodeIfPresent(Date.self, forKey: .dateCreated)
        self.dateModified = try? c.decodeIfPresent(Date.self, forKey: .dateModified)
    }

    private static func flexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }

    private static func flexibleBool(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Bool? {
        if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s == "1" || s.lowercased() == "true" }
        return nil
    }

    func toModel() -> InlineComment {
        InlineComment(
            id: id,
            phid: phid,
            authorPHID: authorPHID,
            diffID: diffID,
            path: filePath,
            line: lineNumber,
            length: lineLength,
            isNewFile: isNewFile,
            isDeleted: isDeleted ?? false,
            replyToCommentPHID: replyToCommentPHID,
            transactionPHID: transactionPHID,
            content: content,
            dateCreated: dateCreated,
            dateModified: dateModified
        )
    }
}
