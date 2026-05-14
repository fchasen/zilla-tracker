//
//  BugDraft.swift
//  Zilla
//

import Foundation
import SwiftData
import BugzillaKit

typealias BugDraft = ZillaSchemaV2.BugDraft

extension BugDraft {
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
