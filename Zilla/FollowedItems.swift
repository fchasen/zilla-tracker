//
//  FollowedItems.swift
//  Zilla
//

import Foundation
import SwiftData
import BugzillaKit

typealias FollowedComponent = ZillaSchemaV2.FollowedComponent
typealias FollowedMetaBug = ZillaSchemaV2.FollowedMetaBug

extension FollowedComponent {
    var ref: ComponentRef {
        ComponentRef(product: product, component: componentName)
    }
}

extension FollowedMetaBug {
    static func cleanedSummary(_ summary: String) -> String {
        let stripped = summary.replacingOccurrences(
            of: #"^\s*\[meta\]\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
