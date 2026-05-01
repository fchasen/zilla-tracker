import SwiftUI

struct InspectorSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .scaledFont(.caption2, weight: .semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            if let trailing {
                Text(trailing)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Add via quick search")
            }
        }
    }
}
