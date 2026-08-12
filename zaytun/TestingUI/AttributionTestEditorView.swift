import SwiftData
import SwiftUI

struct AttributionTestEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.createdAt) private var people: [Person]
    let material: Material

    @State private var selectedPersonID: UUID?
    @State private var role: AttributionRole = .createdBy
    @State private var isAddingPerson = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Attribution") {
                Picker("Person", selection: $selectedPersonID) {
                    Text("Select a Person").tag(UUID?.none)
                    ForEach(people) { person in
                        Text(person.displayName).tag(Optional(person.id))
                    }
                }
                Picker("Role", selection: $role) {
                    ForEach(AttributionRole.supported) { role in
                        Text(role.displayName).tag(role)
                    }
                }
            }
            Section {
                Button("Create Person") { isAddingPerson = true }
            }
        }
        .navigationTitle("Add Attribution")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    modelContext.rollback()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(selectedPersonID == nil)
            }
        }
        .sheet(isPresented: $isAddingPerson) {
            NavigationStack {
                NewPersonView(savesImmediately: false) { person in selectedPersonID = person.id }
            }
        }
        .interactiveDismissDisabled()
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            guard let selectedPersonID,
                  let person = people.first(where: { $0.id == selectedPersonID }) else {
                throw MaterialEditorError.missingPerson
            }
            try AttributionService.create(
                material: material,
                person: person,
                role: role,
                in: modelContext
            )
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
