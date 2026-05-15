//
//  ZillaSchema.swift
//  Zilla
//

import Foundation
import SwiftData
import BugzillaKit

enum ZillaSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FollowedComponent.self,
            FollowedMetaBug.self,
            BugDraft.self,
            BugOrderEntry.self,
            InlineDraftBuffer.self
        ]
    }

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

    @Model
    final class BugDraft {
        @Attribute(.unique) var id: UUID = UUID()
        var summary: String = ""
        var bugDescription: String = ""
        var product: String = ""
        var componentName: String = ""
        var version: String = "unspecified"
        var type: String?
        var severity: String?
        var priority: String?
        var assignedTo: String?
        var keywordsCSV: String = ""
        var whiteboard: String = ""
        var blocks: [Int] = []
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(product: String = "", componentName: String = "", blocks: [Int] = []) {
            self.id = UUID()
            self.product = product
            self.componentName = componentName
            self.blocks = blocks
            let now = Date.now
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class BugOrderEntry {
        var endpointKey: String = ""
        var bugId: Int = 0
        var position: Int = 0
        var addedAt: Date = Date()

        init(endpointKey: String, bugId: Int, position: Int = 0, addedAt: Date = .now) {
            self.endpointKey = endpointKey
            self.bugId = bugId
            self.position = position
            self.addedAt = addedAt
        }
    }

    @Model
    final class InlineDraftBuffer {
        @Attribute(.unique) var id: UUID = UUID()
        var revisionID: Int
        var diffID: Int
        var path: String
        var line: Int
        var length: Int
        var isNewFile: Bool
        var replyTo: String?
        var content: String
        var updatedAt: Date

        init(
            revisionID: Int,
            diffID: Int,
            path: String,
            line: Int,
            length: Int,
            isNewFile: Bool,
            replyTo: String?,
            content: String
        ) {
            self.revisionID = revisionID
            self.diffID = diffID
            self.path = path
            self.line = line
            self.length = length
            self.isNewFile = isNewFile
            self.replyTo = replyTo
            self.content = content
            self.updatedAt = .now
        }
    }
}

enum ZillaSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FollowedComponent.self,
            FollowedMetaBug.self,
            BugDraft.self,
            BugOrderEntry.self,
            InlineDraftBuffer.self
        ]
    }

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
            self.summary = cleanedMetaBugSummary(summary)
            self.component = component
            self.position = position
            self.addedAt = addedAt
        }
    }

    @Model
    final class BugDraft {
        var id: UUID = UUID()
        var summary: String = ""
        var bugDescription: String = ""
        var product: String = ""
        var componentName: String = ""
        var version: String = "unspecified"
        var type: String?
        var severity: String?
        var priority: String?
        var assignedTo: String?
        var keywordsCSV: String = ""
        var whiteboard: String = ""
        var blocks: [Int] = []
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(product: String = "", componentName: String = "", blocks: [Int] = []) {
            self.id = UUID()
            self.product = product
            self.componentName = componentName
            self.blocks = blocks
            let now = Date.now
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class BugOrderEntry {
        var endpointKey: String = ""
        var bugId: Int = 0
        var position: Int = 0
        var addedAt: Date = Date()

        init(endpointKey: String, bugId: Int, position: Int = 0, addedAt: Date = .now) {
            self.endpointKey = endpointKey
            self.bugId = bugId
            self.position = position
            self.addedAt = addedAt
        }
    }

    @Model
    final class InlineDraftBuffer {
        var id: UUID = UUID()
        var revisionID: Int = 0
        var diffID: Int = 0
        var path: String = ""
        var line: Int = 0
        var length: Int = 0
        var isNewFile: Bool = false
        var replyTo: String?
        var content: String = ""
        var updatedAt: Date = Date()

        init(
            revisionID: Int,
            diffID: Int,
            path: String,
            line: Int,
            length: Int,
            isNewFile: Bool,
            replyTo: String?,
            content: String
        ) {
            self.revisionID = revisionID
            self.diffID = diffID
            self.path = path
            self.line = line
            self.length = length
            self.isNewFile = isNewFile
            self.replyTo = replyTo
            self.content = content
            self.updatedAt = .now
        }
    }
}

enum ZillaSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            FollowedComponent.self,
            FollowedMetaBug.self,
            BugDraft.self,
            BugOrderEntry.self,
            InlineDraftBuffer.self
        ]
    }

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
            self.summary = cleanedMetaBugSummary(summary)
            self.component = component
            self.position = position
            self.addedAt = addedAt
        }
    }

    @Model
    final class BugDraft {
        var id: UUID = UUID()
        var summary: String = ""
        var bugDescription: String = ""
        var product: String = ""
        var componentName: String = ""
        var version: String = "unspecified"
        var type: String?
        var severity: String?
        var priority: String?
        var assignedTo: String?
        var keywordsCSV: String = ""
        var whiteboard: String = ""
        var blocks: [Int] = []
        var isConfidential: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(product: String = "", componentName: String = "", blocks: [Int] = []) {
            self.id = UUID()
            self.product = product
            self.componentName = componentName
            self.blocks = blocks
            let now = Date.now
            self.createdAt = now
            self.updatedAt = now
        }
    }

    @Model
    final class BugOrderEntry {
        var endpointKey: String = ""
        var bugId: Int = 0
        var position: Int = 0
        var addedAt: Date = Date()

        init(endpointKey: String, bugId: Int, position: Int = 0, addedAt: Date = .now) {
            self.endpointKey = endpointKey
            self.bugId = bugId
            self.position = position
            self.addedAt = addedAt
        }
    }

    @Model
    final class InlineDraftBuffer {
        var id: UUID = UUID()
        var revisionID: Int = 0
        var diffID: Int = 0
        var path: String = ""
        var line: Int = 0
        var length: Int = 0
        var isNewFile: Bool = false
        var replyTo: String?
        var content: String = ""
        var updatedAt: Date = Date()

        init(
            revisionID: Int,
            diffID: Int,
            path: String,
            line: Int,
            length: Int,
            isNewFile: Bool,
            replyTo: String?,
            content: String
        ) {
            self.revisionID = revisionID
            self.diffID = diffID
            self.path = path
            self.line = line
            self.length = length
            self.isNewFile = isNewFile
            self.replyTo = replyTo
            self.content = content
            self.updatedAt = .now
        }
    }
}

enum ZillaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ZillaSchemaV1.self, ZillaSchemaV2.self, ZillaSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: ZillaSchemaV1.self, toVersion: ZillaSchemaV2.self),
            .lightweight(fromVersion: ZillaSchemaV2.self, toVersion: ZillaSchemaV3.self)
        ]
    }
}
