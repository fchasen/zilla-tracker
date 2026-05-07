import SwiftUI

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

    var detail: String {
        switch self {
        case .approved: return "Adequate automated tests are included."
        case .exceptionUnchanged: return "No runtime behavior change in this revision."
        case .exceptionUI: return "Pure UI work; not exercisable by unit tests."
        case .exceptionElsewhere: return "Behavior is covered by tests in another module."
        case .exceptionOther: return "Other reason; explain in the comments."
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
}
