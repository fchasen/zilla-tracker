//
//  ComponentPickerSheet.swift
//  Zilla
//

import SwiftUI
import SwiftData
import BugzillaKit

struct ComponentPickerSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existing: [FollowedComponent]

    var onPick: ((Product, Component) -> Void)? = nil

    @State private var selectedProduct: Product?
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if let product = selectedProduct {
                    ComponentList(
                        product: product,
                        alreadyFollowed: alreadyFollowed,
                        onPick: addComponent
                    )
                } else {
                    productPane
                }
            }
            .navigationTitle(selectedProduct?.name ?? (onPick == nil ? "Add Component" : "Pick Component"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selectedProduct != nil {
                        Button("Back") { selectedProduct = nil }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
        #endif
        .task {
            if workspace.products.isEmpty {
                await workspace.loadProducts(using: auth.client)
            }
        }
    }

    @ViewBuilder
    private var productPane: some View {
        if workspace.products.isEmpty {
            if workspace.isLoadingProducts {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = workspace.loadError {
                ContentUnavailableView(
                    "Couldn't load products",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ContentUnavailableView(
                    "No accessible products",
                    systemImage: "shippingbox",
                    description: Text("Your account doesn't have access to any active products.")
                )
            }
        } else {
            List(filteredProducts) { product in
                Button {
                    selectedProduct = product
                } label: {
                    HStack {
                        Label(product.name, systemImage: "shippingbox")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(activeComponentCount(in: product))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Filter products")
        }
    }

    private var filteredProducts: [Product] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return workspace.products }
        return workspace.products.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func activeComponentCount(in product: Product) -> Int {
        product.components.filter(\.isActive).count
    }

    private var alreadyFollowed: Set<ComponentRef> {
        // For draft picking, every component is pickable (we're not following).
        guard onPick == nil else { return [] }
        return Set(existing.map(\.ref))
    }

    private func addComponent(_ product: Product, _ component: Component) {
        if let onPick {
            onPick(product, component)
        } else {
            let nextPosition = (existing.map(\.position).max() ?? -1) + 1
            let f = FollowedComponent(
                product: product.name,
                componentName: component.name,
                position: nextPosition
            )
            modelContext.insert(f)
        }
        dismiss()
    }
}

private struct ComponentList: View {
    let product: Product
    let alreadyFollowed: Set<ComponentRef>
    let onPick: (Product, Component) -> Void

    @State private var search: String = ""

    var body: some View {
        List(filtered) { component in
            let ref = ComponentRef(product: product.name, component: component.name)
            let followed = alreadyFollowed.contains(ref)
            Button {
                if !followed { onPick(product, component) }
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(component.name)
                            .foregroundStyle(.primary)
                        if !component.description.isEmpty {
                            Text(component.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if followed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(followed)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter components")
    }

    private var filtered: [Component] {
        let active = product.components
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return active }
        return active.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.description.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
