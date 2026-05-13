import Foundation

public struct Product: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String
    public let isActive: Bool
    public let defaultMilestone: String?
    public let milestones: [ProductMilestone]
    public let components: [Component]

    public init(
        id: Int,
        name: String,
        description: String,
        isActive: Bool,
        components: [Component],
        defaultMilestone: String? = nil,
        milestones: [ProductMilestone] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isActive = isActive
        self.components = components
        self.defaultMilestone = defaultMilestone
        self.milestones = milestones
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, isActive, defaultMilestone, milestones, components
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        self.defaultMilestone = try c.decodeIfPresent(String.self, forKey: .defaultMilestone)
        self.milestones = try c.decodeIfPresent([ProductMilestone].self, forKey: .milestones) ?? []
        self.components = try c.decodeIfPresent([Component].self, forKey: .components) ?? []
    }
}

public struct ProductMilestone: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let isActive: Bool
    public let sortKey: Int

    public init(id: Int, name: String, isActive: Bool = true, sortKey: Int = 0) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.sortKey = sortKey
    }
}

public struct Component: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String
    public let defaultAssignedTo: String?
    public let triageOwner: String?
    public let isActive: Bool

    public init(
        id: Int,
        name: String,
        description: String,
        defaultAssignedTo: String? = nil,
        triageOwner: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.defaultAssignedTo = defaultAssignedTo
        self.triageOwner = triageOwner
        self.isActive = isActive
    }
}

public struct ComponentRef: Codable, Sendable, Hashable {
    public let product: String
    public let component: String

    public init(product: String, component: String) {
        self.product = product
        self.component = component
    }
}
