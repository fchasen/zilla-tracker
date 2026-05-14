import Foundation

public struct Bug: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let summary: String
    public let status: String
    public let resolution: String
    public let product: String
    public let component: String
    public let assignedTo: String?
    public let creator: String?
    public let reporter: String?
    public let creationTime: Date?
    public let lastChangeTime: Date?
    public let priority: String?
    public let severity: String?
    public let keywords: [String]
    public let whiteboard: String?
    public let blocks: [Int]
    public let dependsOn: [Int]
    public let seeAlso: [String]
    public let cc: [String]
    public let flags: [Flag]
    public let type: String?
    public let targetMilestone: String?
    public let points: String?
    public let accessibilitySeverity: String?
    public let rank: Int?
    public let assignedToDetail: User?
    public let creatorDetail: User?
    public let attachments: [Attachment]

    public init(
        id: ID,
        summary: String,
        status: String,
        resolution: String,
        product: String,
        component: String,
        assignedTo: String? = nil,
        creator: String? = nil,
        reporter: String? = nil,
        creationTime: Date? = nil,
        lastChangeTime: Date? = nil,
        priority: String? = nil,
        severity: String? = nil,
        keywords: [String] = [],
        whiteboard: String? = nil,
        blocks: [Int] = [],
        dependsOn: [Int] = [],
        seeAlso: [String] = [],
        cc: [String] = [],
        flags: [Flag] = [],
        type: String? = nil,
        targetMilestone: String? = nil,
        points: String? = nil,
        accessibilitySeverity: String? = nil,
        rank: Int? = nil,
        assignedToDetail: User? = nil,
        creatorDetail: User? = nil,
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.summary = summary
        self.status = status
        self.resolution = resolution
        self.product = product
        self.component = component
        self.assignedTo = assignedTo
        self.creator = creator
        self.reporter = reporter
        self.creationTime = creationTime
        self.lastChangeTime = lastChangeTime
        self.priority = priority
        self.severity = severity
        self.keywords = keywords
        self.whiteboard = whiteboard
        self.blocks = blocks
        self.dependsOn = dependsOn
        self.seeAlso = seeAlso
        self.cc = cc
        self.flags = flags
        self.type = type
        self.targetMilestone = targetMilestone
        self.points = points
        self.accessibilitySeverity = accessibilitySeverity
        self.rank = rank
        self.assignedToDetail = assignedToDetail
        self.creatorDetail = creatorDetail
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, summary, status, resolution, product, component
        case assignedTo, creator, reporter
        case creationTime, lastChangeTime
        case priority, severity, keywords, whiteboard
        case blocks, dependsOn, seeAlso, cc, flags
        case type, targetMilestone, attachments
        case points = "cfFxPoints"
        case accessibilitySeverity = "cfAccessibilitySeverity"
        case rank = "cfRank"
        case assignedToDetail, creatorDetail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.resolution = try c.decodeIfPresent(String.self, forKey: .resolution) ?? ""
        self.product = try c.decodeIfPresent(String.self, forKey: .product) ?? ""
        self.component = try c.decodeIfPresent(String.self, forKey: .component) ?? ""
        self.assignedTo = try c.decodeIfPresent(String.self, forKey: .assignedTo)
        self.creator = try c.decodeIfPresent(String.self, forKey: .creator)
        self.reporter = try c.decodeIfPresent(String.self, forKey: .reporter)
        self.creationTime = try c.decodeIfPresent(Date.self, forKey: .creationTime)
        self.lastChangeTime = try c.decodeIfPresent(Date.self, forKey: .lastChangeTime)
        self.priority = try c.decodeIfPresent(String.self, forKey: .priority)
        self.severity = try c.decodeIfPresent(String.self, forKey: .severity)
        self.keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.whiteboard = try c.decodeIfPresent(String.self, forKey: .whiteboard)
        self.blocks = try c.decodeIfPresent([Int].self, forKey: .blocks) ?? []
        self.dependsOn = try c.decodeIfPresent([Int].self, forKey: .dependsOn) ?? []
        self.seeAlso = try c.decodeIfPresent([String].self, forKey: .seeAlso) ?? []
        self.cc = try c.decodeIfPresent([String].self, forKey: .cc) ?? []
        self.flags = try c.decodeIfPresent([Flag].self, forKey: .flags) ?? []
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.targetMilestone = try c.decodeIfPresent(String.self, forKey: .targetMilestone)
        self.points = try c.decodeIfPresent(String.self, forKey: .points)
        self.accessibilitySeverity = try c.decodeIfPresent(String.self, forKey: .accessibilitySeverity)
        if let i = try? c.decodeIfPresent(Int.self, forKey: .rank) {
            self.rank = i
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .rank), let i = Int(s) {
            self.rank = i
        } else {
            self.rank = nil
        }
        self.assignedToDetail = try c.decodeIfPresent(User.self, forKey: .assignedToDetail)
        self.creatorDetail = try c.decodeIfPresent(User.self, forKey: .creatorDetail)
        self.attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }

    public var isMeta: Bool {
        keywords.contains("meta")
    }

    public var hasPhabricatorPatch: Bool {
        attachments.contains { $0.contentType == "text/x-phabricator-request" && !$0.isObsolete }
    }
}

public struct BugSearchResult: Codable, Sendable {
    public let bugs: [Bug]
    public let totalMatches: Int?

    public init(bugs: [Bug], totalMatches: Int? = nil) {
        self.bugs = bugs
        self.totalMatches = totalMatches
    }
}

public struct Flag: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let status: String
    public let setter: String?
    public let requestee: String?
    public let typeID: Int?
    public let creationDate: Date?
    public let modificationDate: Date?
}

public struct BugRelationUpdate: Sendable, Equatable, Encodable {
    public var add: [Bug.ID]?
    public var remove: [Bug.ID]?
    public var set: [Bug.ID]?

    public init(add: [Bug.ID]? = nil, remove: [Bug.ID]? = nil, set: [Bug.ID]? = nil) {
        self.add = add
        self.remove = remove
        self.set = set
    }

    public static func add(_ ids: [Bug.ID]) -> BugRelationUpdate {
        BugRelationUpdate(add: ids)
    }

    public static func remove(_ ids: [Bug.ID]) -> BugRelationUpdate {
        BugRelationUpdate(remove: ids)
    }

    private enum CodingKeys: String, CodingKey {
        case add, remove, set
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(add, forKey: .add)
        try c.encodeIfPresent(remove, forKey: .remove)
        try c.encodeIfPresent(set, forKey: .set)
    }
}

public struct SeeAlsoUpdate: Sendable, Equatable, Encodable {
    public var add: [String]?
    public var remove: [String]?

    public init(add: [String]? = nil, remove: [String]? = nil) {
        self.add = add
        self.remove = remove
    }

    public static func add(_ urls: [String]) -> SeeAlsoUpdate {
        SeeAlsoUpdate(add: urls)
    }

    public static func remove(_ urls: [String]) -> SeeAlsoUpdate {
        SeeAlsoUpdate(remove: urls)
    }

    private enum CodingKeys: String, CodingKey {
        case add, remove
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(add, forKey: .add)
        try c.encodeIfPresent(remove, forKey: .remove)
    }
}

public struct FlagUpdate: Sendable, Equatable, Encodable {
    public var id: Int?
    public var name: String?
    public var status: String
    public var requestee: String?

    public init(
        id: Int? = nil,
        name: String? = nil,
        status: String,
        requestee: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.requestee = requestee
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, status, requestee
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(requestee, forKey: .requestee)
    }
}

public struct BugUpdate: Sendable, Equatable {
    public var summary: String?
    public var status: String?
    public var resolution: String?
    public var dupeOf: Bug.ID?
    public var assignedTo: String?
    public var priority: String?
    public var severity: String?
    public var targetMilestone: String?
    public var points: String?
    public var rank: Int?
    public var comment: String?
    public var commentIsPrivate: Bool?
    public var blocks: BugRelationUpdate?
    public var dependsOn: BugRelationUpdate?
    public var seeAlso: SeeAlsoUpdate?
    public var flags: [FlagUpdate]?

    public init(
        summary: String? = nil,
        status: String? = nil,
        resolution: String? = nil,
        dupeOf: Bug.ID? = nil,
        assignedTo: String? = nil,
        priority: String? = nil,
        severity: String? = nil,
        targetMilestone: String? = nil,
        points: String? = nil,
        rank: Int? = nil,
        comment: String? = nil,
        commentIsPrivate: Bool? = nil,
        blocks: BugRelationUpdate? = nil,
        dependsOn: BugRelationUpdate? = nil,
        seeAlso: SeeAlsoUpdate? = nil,
        flags: [FlagUpdate]? = nil
    ) {
        self.summary = summary
        self.status = status
        self.resolution = resolution
        self.dupeOf = dupeOf
        self.assignedTo = assignedTo
        self.priority = priority
        self.severity = severity
        self.targetMilestone = targetMilestone
        self.points = points
        self.rank = rank
        self.comment = comment
        self.commentIsPrivate = commentIsPrivate
        self.blocks = blocks
        self.dependsOn = dependsOn
        self.seeAlso = seeAlso
        self.flags = flags
    }
}

public struct BugCreate: Sendable, Equatable {
    public var product: String
    public var component: String
    public var summary: String
    public var version: String
    public var description: String?
    public var type: String?
    public var severity: String?
    public var priority: String?
    public var assignedTo: String?
    public var keywords: [String]
    public var whiteboard: String?
    public var blocks: [Int]
    public var dependsOn: [Int]
    public var cc: [String]

    public init(
        product: String,
        component: String,
        summary: String,
        version: String = "unspecified",
        description: String? = nil,
        type: String? = nil,
        severity: String? = nil,
        priority: String? = nil,
        assignedTo: String? = nil,
        keywords: [String] = [],
        whiteboard: String? = nil,
        blocks: [Int] = [],
        dependsOn: [Int] = [],
        cc: [String] = []
    ) {
        self.product = product
        self.component = component
        self.summary = summary
        self.version = version
        self.description = description
        self.type = type
        self.severity = severity
        self.priority = priority
        self.assignedTo = assignedTo
        self.keywords = keywords
        self.whiteboard = whiteboard
        self.blocks = blocks
        self.dependsOn = dependsOn
        self.cc = cc
    }
}

public struct BugChangeResult: Codable, Sendable, Hashable, Identifiable {
    public let id: Bug.ID
    public let lastChangeTime: Date?
    public let changes: [String: BugFieldChange]
}

public struct BugFieldChange: Codable, Sendable, Hashable {
    public let removed: String
    public let added: String
}

public struct Comment: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let bugId: Bug.ID
    public let creator: String
    public let text: String
    public let creationTime: Date
    public let isPrivate: Bool
    public let count: Int?
    public let attachmentId: Attachment.ID?

    private enum CodingKeys: String, CodingKey {
        case id, bugId, creator, text, creationTime, isPrivate, count, attachmentId
    }

    public init(
        id: ID,
        bugId: Bug.ID,
        creator: String,
        text: String,
        creationTime: Date,
        isPrivate: Bool,
        count: Int?,
        attachmentId: Attachment.ID? = nil
    ) {
        self.id = id
        self.bugId = bugId
        self.creator = creator
        self.text = text
        self.creationTime = creationTime
        self.isPrivate = isPrivate
        self.count = count
        self.attachmentId = attachmentId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.bugId = try c.decodeIfPresent(Int.self, forKey: .bugId) ?? 0
        self.creator = try c.decodeIfPresent(String.self, forKey: .creator) ?? ""
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.creationTime = try c.decodeIfPresent(Date.self, forKey: .creationTime) ?? .distantPast
        if let b = try? c.decode(Bool.self, forKey: .isPrivate) {
            self.isPrivate = b
        } else if let i = try? c.decode(Int.self, forKey: .isPrivate) {
            self.isPrivate = i != 0
        } else {
            self.isPrivate = false
        }
        self.count = try c.decodeIfPresent(Int.self, forKey: .count)
        self.attachmentId = try c.decodeIfPresent(Int.self, forKey: .attachmentId)
    }
}

public struct Attachment: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let bugId: Bug.ID
    public let fileName: String
    public let summary: String
    public let contentType: String
    public let creator: String
    public let creationTime: Date
    public let lastChangeTime: Date?
    public let size: Int?
    public let isObsolete: Bool
    public let isPatch: Bool
    public let isPrivate: Bool
    public let data: String?
    public let flags: [Flag]

    public init(
        id: ID,
        bugId: Bug.ID = 0,
        fileName: String = "",
        summary: String = "",
        contentType: String = "",
        creator: String = "",
        creationTime: Date = .distantPast,
        lastChangeTime: Date? = nil,
        size: Int? = nil,
        isObsolete: Bool = false,
        isPatch: Bool = false,
        isPrivate: Bool = false,
        data: String? = nil,
        flags: [Flag] = []
    ) {
        self.id = id
        self.bugId = bugId
        self.fileName = fileName
        self.summary = summary
        self.contentType = contentType
        self.creator = creator
        self.creationTime = creationTime
        self.lastChangeTime = lastChangeTime
        self.size = size
        self.isObsolete = isObsolete
        self.isPatch = isPatch
        self.isPrivate = isPrivate
        self.data = data
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey {
        case id, bugId, fileName, summary, contentType, creator
        case creationTime, lastChangeTime, size
        case isObsolete, isPatch, isPrivate, data, flags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.bugId = try c.decodeIfPresent(Int.self, forKey: .bugId) ?? 0
        self.fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        self.creator = try c.decodeIfPresent(String.self, forKey: .creator) ?? ""
        self.creationTime = try c.decodeIfPresent(Date.self, forKey: .creationTime) ?? .distantPast
        self.lastChangeTime = try c.decodeIfPresent(Date.self, forKey: .lastChangeTime)
        self.size = try c.decodeIfPresent(Int.self, forKey: .size)
        self.isObsolete = Self.decodeFlexibleBool(c, key: .isObsolete)
        self.isPatch = Self.decodeFlexibleBool(c, key: .isPatch)
        self.isPrivate = Self.decodeFlexibleBool(c, key: .isPrivate)
        self.data = try c.decodeIfPresent(String.self, forKey: .data)
        self.flags = try c.decodeIfPresent([Flag].self, forKey: .flags) ?? []
    }

    private static func decodeFlexibleBool(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return false
    }
}

public struct HistoryEntry: Codable, Sendable, Hashable {
    public let when: Date
    public let who: String
    public let changes: [Change]
}

public struct Change: Codable, Sendable, Hashable {
    public let fieldName: String
    public let removed: String
    public let added: String
    public let attachmentID: Int?
}
