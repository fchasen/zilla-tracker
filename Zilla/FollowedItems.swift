//
//  FollowedItems.swift
//  Zilla
//

import Foundation
import SwiftData
import BugzillaKit

@Model
final class FollowedComponent {
    var product: String = ""
    var componentName: String = ""
    var addedAt: Date = Date()
    var position: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \FollowedMetaBug.component)
    var metaBugs: [FollowedMetaBug] = []

    init(product: String, componentName: String, position: Int = 0, addedAt: Date = .now) {
        self.product = product
        self.componentName = componentName
        self.position = position
        self.addedAt = addedAt
    }

    var ref: ComponentRef {
        ComponentRef(product: product, component: componentName)
    }
}

@Model
final class FollowedMetaBug {
    var bugId: Int = 0
    var summary: String = ""
    var addedAt: Date = Date()
    var position: Int = 0
    var component: FollowedComponent?

    init(bugId: Int, summary: String, component: FollowedComponent?, position: Int = 0, addedAt: Date = .now) {
        self.bugId = bugId
        self.summary = summary
        self.component = component
        self.position = position
        self.addedAt = addedAt
    }
}
