import SwiftData
import SwiftUI

private struct AttributionDraft: Identifiable {
    let id = UUID()
    var personID: UUID
    var role: AttributionRole = .createdBy
}

struct MaterialTestEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.createdAt) private var people: [Person]

    @State private var type: MaterialType = .note
    @State private var title = ""
    @State private var text = ""
    @State private var source = ""
    @State private var attributionDrafts: [AttributionDraft] = []
    @State private var isAddingPerson = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Material") {
                Picker("Type", selection: $type) {
                    ForEach(MaterialType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Optional title", text: $title)
                if type == .note {
                    TextEditor(text: $text)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Note text")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                TextField("Optional source (for example, WhatsApp)", text: $source)
            }

            Section {
                ForEach($attributionDrafts) { $draft in
                    VStack(alignment: .leading) {
                        Picker("Person", selection: $draft.personID) {
                            ForEach(people) { person in
                                Text(person.displayName).tag(person.id)
                            }
                        }
                        Picker("Role", selection: $draft.role) {
                            ForEach(AttributionRole.supported) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            attributionDrafts.removeAll { $0.id == draft.id }
                        }
                    }
                }

                Button {
                    if let firstPerson = people.first {
                        attributionDrafts.append(AttributionDraft(personID: firstPerson.id))
                    } else {
                        isAddingPerson = true
                    }
                } label: {
                    Label("Add Attribution", systemImage: "person.badge.plus")
                }

                Button {
                    isAddingPerson = true
                } label: {
                    Label("Create Person", systemImage: "plus")
                }
            } header: {
                Text("People (Optional)")
            } footer: {
                Text("Source records where you encountered something. People and roles record who was involved and how.")
            }
        }
        .navigationTitle("Add Material")
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
            }
        }
        .sheet(isPresented: $isAddingPerson) {
            NavigationStack {
                NewPersonView(savesImmediately: false) { person in
                    attributionDrafts.append(AttributionDraft(personID: person.id))
                }
            }
        }
        .interactiveDismissDisabled()
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            let resolvedDrafts = try attributionDrafts.map { draft in
                guard let person = people.first(where: { $0.id == draft.personID }) else {
                    throw MaterialEditorError.missingPerson
                }
                return (person: person, role: draft.role)
            }
            let material = Material(
                type: type,
                title: title.trimmedNonempty,
                text: type == .note ? text.trimmedNonempty : nil,
                source: source.trimmedNonempty
            )
            modelContext.insert(material)
            for value in resolvedDrafts {
                try AttributionService.create(
                    material: material,
                    person: value.person,
                    role: value.role,
                    in: modelContext
                )
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

enum MaterialEditorError: LocalizedError {
    case missingPerson

    var errorDescription: String? {
        String(localized: "A selected Person no longer exists.")
    }
}
