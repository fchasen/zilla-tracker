import SwiftUI
import PhabricatorKit

enum TestingTag: String, CaseIterable, Identifiable, Hashable {
    case approved = "testing-approved"
    case exceptionUnchanged = "testing-exception-unchanged"
    case exceptionUI = "testing-exception-ui"
    case exceptionElsewhere = "testing-exception-elsewhere"
    case exceptionOther = "testing-exception-other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approved: return "Tests approved"
        case .exceptionUnchanged: return "No behavior change"
        case .exceptionUI: return "UI only"
        case .exceptionElsewhere: return "Tested elsewhere"
        case .exceptionOther: return "Exception (other)"
        }
    }

    var systemImage: String {
        switch self {
        case .approved: return "checkmark.seal.fill"
        case .exceptionUnchanged: return "equal.circle.fill"
        case .exceptionUI: return "rectangle.on.rectangle"
        case .exceptionElsewhere: return "arrow.up.right.square.fill"
        case .exceptionOther: return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .approved: return .green
        default: return .orange
        }
    }

    static func match(_ project: PhabricatorProject) -> TestingTag? {
        for tag in TestingTag.allCases {
            let raw = tag.rawValue
            if project.name == raw || project.name.hasPrefix(raw + " ") {
                return tag
            }
            if let slug = project.slug, slug == raw || slug.hasPrefix(raw + "_") {
                return tag
            }
        }
        return nil
    }
}
