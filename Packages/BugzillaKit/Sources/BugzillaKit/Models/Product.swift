import Foundation

public struct Product: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String
    public let isActive: Bool
    public let components: [Component]

    public init(id: Int, name: String, description: String, isActive: Bool, components: [Component]) {
        self.id = id
        self.name = name
        self.description = description
        self.isActive = isActive
        self.components = components
    }
}

public struct Component: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String
    public let defaultAssignee: String?
    public let isActive: Bool

    public init(id: Int, name: String, description: String, defaultAssignee: String? = nil, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.defaultAssignee = defaultAssignee
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
