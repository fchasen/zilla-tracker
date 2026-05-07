import SwiftUI
import PhabricatorKit

struct StatusBadge: View {
    let status: RevisionStatus

    var body: some View {
        Text(status.name)
            .scaledFont(.caption, weight: .medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    var color: Color { Self.color(for: status) }

    static func color(for status: RevisionStatus) -> Color {
        switch status.value {
        case RevisionStatus.Value.needsReview: return .orange
        case RevisionStatus.Value.needsRevision: return .red
        case RevisionStatus.Value.accepted: return .green
        case RevisionStatus.Value.changesPlanned: return .yellow
        case RevisionStatus.Value.draft: return .gray
        case RevisionStatus.Value.published: return .blue
        case RevisionStatus.Value.abandoned: return .secondary
        default: return .secondary
        }
    }
}
