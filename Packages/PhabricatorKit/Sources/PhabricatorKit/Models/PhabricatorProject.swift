import Foundation

public struct PhabricatorProject: Sendable, Hashable, Identifiable {
    public let phid: String
    public let id: Int
    public let name: String
    public let slug: String?
    public let icon: String?
    public let color: String?

    public init(phid: String, id: Int, name: String, slug: String? = nil, icon: String? = nil, color: String? = nil) {
        self.phid = phid
        self.id = id
        self.name = name
        self.slug = slug
        self.icon = icon
        self.color = color
    }
}

extension PhabricatorProject: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopKeys.self)
        let phid = try c.decode(String.self, forKey: .phid)
        let rawID = try c.decode(IntOrString.self, forKey: .id).intValue
        let fields = try c.decode(Fields.self, forKey: .fields)
        self.phid = phid
        self.id = rawID
        self.name = fields.name
        self.slug = fields.slug
        self.icon = fields.icon?.key
        self.color = fields.color?.key
    }

    enum TopKeys: String, CodingKey { case phid, id, fields }

    private struct Fields: Decodable {
        let name: String
        let slug: String?
        let icon: NameKey?
        let color: NameKey?
    }

    private struct NameKey: Decodable {
        let key: String?
    }

    private struct IntOrString: Decodable {
        let intValue: Int
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { self.intValue = i; return }
            if let s = try? c.decode(String.self), let i = Int(s) { self.intValue = i; return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "id was neither Int nor numeric String")
        }
    }
}

public struct ProjectSearchResult: Decodable, Sendable {
    public let data: [PhabricatorProject]
    public let cursor: Cursor?

    public struct Cursor: Decodable, Sendable {
        public let limit: Int?
        public let after: String?
        public let before: String?
    }
}
