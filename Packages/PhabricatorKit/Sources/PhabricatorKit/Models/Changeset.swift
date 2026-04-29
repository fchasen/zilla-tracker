import Foundation

public enum ChangesetType: Int, Sendable, Hashable {
    case add = 1
    case change = 2
    case delete = 3
    case moveAway = 4
    case copyAway = 5
    case moveHere = 6
    case copyHere = 7
    case multicopy = 8
    case unknown = -1
}

public enum FileType: Int, Sendable, Hashable {
    case text = 1
    case image = 2
    case binary = 3
    case directory = 4
    case symlink = 5
    case deleted = 6
    case normal = 7
    case unknown = -1
}

public struct Changeset: Decodable, Sendable, Hashable, Identifiable {
    public typealias ID = Int

    public let id: ID
    public let oldPath: String?
    public let currentPath: String
    public let awayPaths: [String]
    public let type: ChangesetType
    public let fileType: FileType
    public let oldFileType: FileType
    public let addLines: Int
    public let delLines: Int
    public let metadata: [String: String]
    public let hunks: [Hunk]

    enum CodingKeys: String, CodingKey {
        case id
        case oldPath = "oldFile"
        case currentPath = "currentFile"
        case awayPaths
        case type = "changeType"
        case fileType
        case oldFileType
        case addLines = "addLines"
        case delLines = "delLines"
        case metadata
        case hunks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try Self.decodeFlexibleInt(c, key: .id) ?? 0
        let rawOld = try c.decodeIfPresent(String.self, forKey: .oldPath)
        self.oldPath = (rawOld?.isEmpty == false) ? rawOld : nil
        self.currentPath = try c.decodeIfPresent(String.self, forKey: .currentPath) ?? ""
        self.awayPaths = try c.decodeIfPresent([String].self, forKey: .awayPaths) ?? []
        let typeRaw = try Self.decodeFlexibleInt(c, key: .type) ?? -1
        self.type = ChangesetType(rawValue: typeRaw) ?? .unknown
        let fileTypeRaw = try Self.decodeFlexibleInt(c, key: .fileType) ?? -1
        self.fileType = FileType(rawValue: fileTypeRaw) ?? .unknown
        let oldFileTypeRaw = try Self.decodeFlexibleInt(c, key: .oldFileType) ?? -1
        self.oldFileType = FileType(rawValue: oldFileTypeRaw) ?? .unknown
        self.addLines = try Self.decodeFlexibleInt(c, key: .addLines) ?? 0
        self.delLines = try Self.decodeFlexibleInt(c, key: .delLines) ?? 0
        let metadataRaw = (try? c.decodeIfPresent([String: AnyDecodable].self, forKey: .metadata)) ?? nil
        if let metadataRaw {
            var dict: [String: String] = [:]
            for (k, v) in metadataRaw {
                dict[k] = v.stringValue
            }
            self.metadata = dict
        } else {
            self.metadata = [:]
        }
        self.hunks = try c.decodeIfPresent([Hunk].self, forKey: .hunks) ?? []
    }

    private static func decodeFlexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }
}

struct AnyDecodable: Decodable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { stringValue = v; return }
        if let v = try? c.decode(Int.self) { stringValue = String(v); return }
        if let v = try? c.decode(Double.self) { stringValue = String(v); return }
        if let v = try? c.decode(Bool.self) { stringValue = String(v); return }
        stringValue = ""
    }
}
