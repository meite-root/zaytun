import SwiftData
import SwiftUI

struct MaterialTestDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var material: Material
    @State private var isAddingAttribution = false
    @State private var attributionToDelete: MaterialAttribution?
    @State private var isDeletingMaterial = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Material") {
                LabeledContent("Type", value: material.type?.displayName ?? "Unsupported")
                if let title = material.title?.trimmedNonempty {
                    LabeledContent("Title", value: title)
                }
                if let text = material.text?.trimmedNonempty {
                    Text(text)
                }
            }

            if let source = material.source?.trimmedNonempty {
                Section("Source") {
                    Text(source)
                }
            }

            Section("Provenance") {
                if material.attributions.isEmpty {
                    Text("No Person attribution")
                        .foregroundStyle(.secondary)
                }
                ForEach(material.attributions.sorted { $0.createdAt < $1.createdAt }) { attribution in
                    AttributionTestRow(attribution: attribution) { newRole in
                        do {
                            try AttributionService.updateRole(of: attribution, to: newRole)
                            try modelContext.save()
                        } catch {
                            modelContext.rollback()
                            errorMessage = error.localizedDescription
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            attributionToDelete = attribution
                        }
                    }
                }

                Button {
                    isAddingAttribution = true
                } label: {
                    Label("Add Attribution", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle(material.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isDeletingMaterial = true
                }
            }
        }
        .sheet(isPresented: $isAddingAttribution) {
            NavigationStack {
                AttributionTestEditorView(material: material)
            }
        }
        .confirmationDialog(
            "Remove this attribution?",
            isPresented: Binding(
                get: { attributionToDelete != nil },
                set: { if !$0 { attributionToDelete = nil } }
            )
        ) {
            Button("Remove Attribution", role: .destructive) {
                guard let attributionToDelete else { return }
                do {
                    modelContext.delete(attributionToDelete)
                    try modelContext.save()
                    self.attributionToDelete = nil
                } catch {
                    modelContext.rollback()
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Material and Person will remain.")
        }
        .confirmationDialog("Delete this Material?", isPresented: $isDeletingMaterial) {
            Button("Delete Material", role: .destructive) {
                do {
                    modelContext.delete(material)
                    try modelContext.save()
                    dismiss()
                } catch {
                    modelContext.rollback()
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its attribution rows will be deleted. People will remain.")
        }
        .errorAlert(message: $errorMessage)
    }
}

private struct AttributionTestRow: View {
    let attribution: MaterialAttribution
    let changeRole: (AttributionRole) -> Void

    var body: some View {
        HStack {
            Text(attribution.person.displayName)
            Spacer()
            Menu(attribution.role.displayName) {
                ForEach(AttributionRole.supported) { role in
                    Button(role.displayName) { changeRole(role) }
                }
            }
        }
    }
}
