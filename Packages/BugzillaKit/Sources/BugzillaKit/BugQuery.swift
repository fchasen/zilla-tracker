import Foundation

public struct BugQuery: Sendable, Hashable {
    public var product: [String]
    public var component: [String]
    public var status: [String]
    public var resolution: [String]
    public var assignedTo: [String]
    public var reporter: [String]
    public var cc: [String]
    public var keywords: [String]
    public var whiteboard: String?
    public var quicksearch: String?
    public var blocks: [Int]
    public var dependsOn: [Int]
    public var flagRequestee: String?
    public var flagName: String?
    public var changedAfter: Date?
    public var userInvolved: String?
    public var limit: Int?
    public var offset: Int?
    public var includeFields: [String]
    public var excludeFields: [String]
    public var extra: [String: [String]]

    public init(
        product: [String] = [],
        component: [String] = [],
        status: [String] = [],
        resolution: [String] = [],
        assignedTo: [String] = [],
        reporter: [String] = [],
        cc: [String] = [],
        keywords: [String] = [],
        whiteboard: String? = nil,
        quicksearch: String? = nil,
        blocks: [Int] = [],
        dependsOn: [Int] = [],
        flagRequestee: String? = nil,
        flagName: String? = nil,
        changedAfter: Date? = nil,
        userInvolved: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        includeFields: [String] = [],
        excludeFields: [String] = [],
        extra: [String: [String]] = [:]
    ) {
        self.product = product
        self.component = component
        self.status = status
        self.resolution = resolution
        self.assignedTo = assignedTo
        self.reporter = reporter
        self.cc = cc
        self.keywords = keywords
        self.whiteboard = whiteboard
        self.quicksearch = quicksearch
        self.blocks = blocks
        self.dependsOn = dependsOn
        self.flagRequestee = flagRequestee
        self.flagName = flagName
        self.changedAfter = changedAfter
        self.userInvolved = userInvolved
        self.limit = limit
        self.offset = offset
        self.includeFields = includeFields
        self.excludeFields = excludeFields
        self.extra = extra
    }
}

public extension BugQuery {
    static let me = "@me"

    static var myOpenBugs: BugQuery {
        BugQuery(resolution: ["---"], assignedTo: [me])
    }

    static var reportedByMe: BugQuery {
        BugQuery(reporter: [me])
    }

    static var needsReviewFromMe: BugQuery {
        BugQuery(flagRequestee: me, flagName: "review")
    }

    static func recentlyChanged(involving user: String, daysBack: Int = 7) -> BugQuery {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) ?? .now
        return BugQuery(changedAfter: cutoff, userInvolved: user)
    }

    static func openIn(component ref: ComponentRef) -> BugQuery {
        BugQuery(product: [ref.product], component: [ref.component], resolution: ["---"])
    }

    static func blockedBy(metaBug id: Bug.ID) -> BugQuery {
        BugQuery(blocks: [id])
    }
}
