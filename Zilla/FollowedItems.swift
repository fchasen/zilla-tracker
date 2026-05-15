//
//  FollowedItems.swift
//  Zilla
//

import Foundation
import SwiftData
import BugzillaKit

typealias FollowedComponent = ZillaSchemaV3.FollowedComponent
typealias FollowedMetaBug = ZillaSchemaV3.FollowedMetaBug

extension FollowedComponent {
    var ref: ComponentRef {
        ComponentRef(product: product, component: componentName)
    }
}

func cleanedMetaBugSummary(_ summary: String) -> String {
    let stripped = summary.replacingOccurrences(
        of: #"^\s*\[meta\]\s*"#,
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension FollowedMetaBug {
    static func cleanedSummary(_ summary: String) -> String {
        cleanedMetaBugSummary(summary)
    }
}
