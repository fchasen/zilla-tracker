import SwiftUI
import PhabricatorKit

struct RevisionDiffView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSectionHeader(title: "Files", trailing: visibleChangesetsCount.map(String.init))

            if workspace.loadedRevisionDiff == nil && workspace.isLoadingRevision {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else if let diff = workspace.loadedRevisionDiff {
                if visibleChangesets(in: diff).isEmpty {
                    ContentUnavailableView(
                        "No changes",
                        systemImage: "doc.plaintext",
                        description: Text("This diff has no file-level changes.")
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleChangesets(in: diff)) { changeset in
                            ChangesetView(changeset: changeset, latestDiffID: diff.id)
                                .id(RevisionDetailView.scrollAnchor(for: changeset.currentPath))
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No diff uploaded yet",
                    systemImage: "tray",
                    description: Text("There's nothing to review on this revision yet.")
                )
            }
        }
    }

    private var visibleChangesetsCount: Int? {
        workspace.loadedRevisionDiff.map { visibleChangesets(in: $0).count }
    }

    private func visibleChangesets(in diff: DiffDetail) -> [Changeset] {
        diff.changesets.filter { $0.type != .moveAway && $0.type != .copyAway }
    }
}
