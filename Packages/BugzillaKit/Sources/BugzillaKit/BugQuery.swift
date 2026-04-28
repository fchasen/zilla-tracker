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
    public var flagNames: [String]
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
        flagNames: [String] = [],
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
        self.flagNames = flagNames
        self.changedAfter = changedAfter
        self.userInvolved = userInvolved
        self.limit = limit
        self.offset = offset
        self.includeFields = includeFields
        self.excludeFields = excludeFields
        self.extra = extra
    }
}

extension BugQuery {
    static let bmoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f
    }()

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        items += .repeating("product", values: product)
        items += .repeating("component", values: component)
        items += .repeating("status", values: status)
        items += .repeating("resolution", values: resolution)
        items += .repeating("assigned_to", values: assignedTo)
        items += .repeating("reporter", values: reporter)
        items += .repeating("cc", values: cc)
        items += .repeating("keywords", values: keywords)
        if !blocks.isEmpty {
            items += .repeating("blocks", values: blocks.map(String.init))
        }
        if !dependsOn.isEmpty {
            items += .repeating("depends_on", values: dependsOn.map(String.init))
        }
        if let whiteboard {
            items.append(URLQueryItem(name: "whiteboard", value: whiteboard))
        }
        if let quicksearch {
            items.append(URLQueryItem(name: "quicksearch", value: quicksearch))
        }
        if let changedAfter {
            items.append(URLQueryItem(
                name: "last_change_time",
                value: Self.bmoDateFormatter.string(from: changedAfter)
            ))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset {
            items.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        if !includeFields.isEmpty {
            items.append(URLQueryItem(name: "include_fields", value: includeFields.joined(separator: ",")))
        }
        if !excludeFields.isEmpty {
            items.append(URLQueryItem(name: "exclude_fields", value: excludeFields.joined(separator: ",")))
        }
        for (key, values) in extra {
            items += .repeating(key, values: values)
        }

        var chartIndex = 1
        if let flagRequestee {
            items.append(URLQueryItem(name: "f\(chartIndex)", value: "requestees.login_name"))
            items.append(URLQueryItem(name: "o\(chartIndex)", value: "equals"))
            items.append(URLQueryItem(name: "v\(chartIndex)", value: flagRequestee))
            chartIndex += 1
        }
        if !flagNames.isEmpty {
            items.append(URLQueryItem(name: "f\(chartIndex)", value: "flagtypes.name"))
            items.append(URLQueryItem(name: "o\(chartIndex)", value: "anyexact"))
            items.append(URLQueryItem(name: "v\(chartIndex)", value: flagNames.joined(separator: ",")))
            chartIndex += 1
        }
        if let userInvolved {
            items.append(URLQueryItem(name: "f\(chartIndex)", value: "OP"))
            items.append(URLQueryItem(name: "j\(chartIndex)", value: "OR"))
            chartIndex += 1
            for field in ["assigned_to", "reporter", "cc", "commenter"] {
                items.append(URLQueryItem(name: "f\(chartIndex)", value: field))
                items.append(URLQueryItem(name: "o\(chartIndex)", value: "equals"))
                items.append(URLQueryItem(name: "v\(chartIndex)", value: userInvolved))
                chartIndex += 1
            }
            items.append(URLQueryItem(name: "f\(chartIndex)", value: "CP"))
        }

        return items
    }
}

public extension BugQuery {
    static let me = "@me"

    /// Returns a copy of this query with the `@me` sentinel replaced by `login`
    /// in every user-valued field. BMO's REST search does not interpret `@me`
    /// the way the web UI does, so callers must resolve it client-side.
    func substitutingMe(with login: String) -> BugQuery {
        var copy = self
        let swap: (String) -> String = { $0 == BugQuery.me ? login : $0 }
        copy.assignedTo = copy.assignedTo.map(swap)
        copy.reporter = copy.reporter.map(swap)
        copy.cc = copy.cc.map(swap)
        if copy.flagRequestee == BugQuery.me { copy.flagRequestee = login }
        if copy.userInvolved == BugQuery.me { copy.userInvolved = login }
        return copy
    }

    static var myOpenBugs: BugQuery {
        BugQuery(resolution: ["---"], assignedTo: [me])
    }

    static var reportedByMe: BugQuery {
        BugQuery(reporter: [me])
    }

    static var needsReviewFromMe: BugQuery {
        BugQuery(flagRequestee: me, flagNames: ["review", "needinfo"])
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
