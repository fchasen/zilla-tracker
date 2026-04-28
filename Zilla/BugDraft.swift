//
//  BugDraft.swift
//  Zilla
//

import Foundation
import SwiftData
import BugzillaKit

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

    init(
        product: String = "",
        componentName: String = "",
        blocks: [Int] = []
    ) {
        self.id = UUID()
        self.product = product
        self.componentName = componentName
        self.blocks = blocks
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }

    var keywords: [String] {
        keywordsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var componentRef: ComponentRef? {
        guard !product.isEmpty, !componentName.isEmpty else { return nil }
        return ComponentRef(product: product, component: componentName)
    }

    var isReadyToSubmit: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !product.isEmpty
            && !componentName.isEmpty
    }

    var displaySummary: String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled draft" : trimmed
    }

    var displaySubtitle: String {
        if !product.isEmpty, !componentName.isEmpty {
            return "\(product) :: \(componentName)"
        }
        if let firstBlocks = blocks.first {
            return "Blocks #\(firstBlocks)"
        }
        return "No component yet"
    }
}
