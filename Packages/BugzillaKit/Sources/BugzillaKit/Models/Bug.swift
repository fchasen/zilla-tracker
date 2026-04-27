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
    public let cc: [String]
    public let flags: [Flag]

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
        cc: [String] = [],
        flags: [Flag] = []
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
        self.cc = cc
        self.flags = flags
    }

    public var isMeta: Bool {
        keywords.contains("meta")
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

public struct Comment: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let bugID: Bug.ID
    public let creator: String
    public let text: String
    public let creationTime: Date
    public let isPrivate: Bool
    public let count: Int?
}

public struct Attachment: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let bugID: Bug.ID
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
