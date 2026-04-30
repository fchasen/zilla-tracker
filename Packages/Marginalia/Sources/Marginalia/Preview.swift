import Foundation
import SwiftUI
import MarginaliaView

struct MarginaliaPreview: View {
    let source: String
    let dialect: Highlighter.Dialect
    let renderer: MarginaliaPreviewRenderer

    var body: some View {
        ScrollView {
            Group {
                if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to preview yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(renderer(source, dialect))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
        }
    }
}
