import SwiftData
import SwiftUI

struct MaterialsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Material.createdAt, order: .reverse) private var materials: [Material]
    @State private var isAddingMaterial = false
    @State private var materialToDelete: Material?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if materials.isEmpty {
                ContentUnavailableView(
                    "No Materials",
                    systemImage: "tray",
                    description: Text("Add a basic Material to exercise the Stage A persistence model.")
                )
            } else {
                ForEach(materials) { material in
                    NavigationLink {
                        MaterialTestDetailView(material: material)
                    } label: {
                        MaterialTestRow(material: material)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            materialToDelete = material
                        }
                    }
                }
            }
        }
        .navigationTitle("Materials")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    PeopleManagementView()
                } label: {
                    Label("Manage People", systemImage: "person.2")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingMaterial = true
                } label: {
                    Label("Add Material", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingMaterial) {
            NavigationStack {
                MaterialTestEditorView()
            }
        }
        .confirmationDialog(
            "Delete this Material?",
            isPresented: Binding(
                get: { materialToDelete != nil },
                set: { if !$0 { materialToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Material", role: .destructive) {
                guard let materialToDelete else { return }
                do {
                    modelContext.delete(materialToDelete)
                    try modelContext.save()
                    self.materialToDelete = nil
                } catch {
                    modelContext.rollback()
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) { materialToDelete = nil }
        } message: {
            Text("Its provenance statements will be removed. People will remain.")
        }
        .errorAlert(message: $errorMessage)
    }
}

private struct MaterialTestRow: View {
    let material: Material

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(material.displayTitle)
                .font(.headline)
            Text(material.type?.displayName ?? "Unsupported type")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let source = material.source?.trimmedNonempty {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let summary = material.attributionSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
