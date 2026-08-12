import SwiftData
import SwiftUI

struct PeopleManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.createdAt) private var people: [Person]
    @State private var isAddingPerson = false
    @State private var personToDelete: Person?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Me") {
                ForEach(people.filter(\.isSelf)) { person in
                    NavigationLink {
                        PersonTestEditorView(person: person)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Me")
                            if let name = person.name?.trimmedNonempty {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Other People") {
                if people.allSatisfy(\.isSelf) {
                    Text("No other People")
                        .foregroundStyle(.secondary)
                }
                ForEach(people.filter { !$0.isSelf }) { person in
                    NavigationLink {
                        PersonTestEditorView(person: person)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(person.displayName)
                            Text("\(person.attributions.count) attribution(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            personToDelete = person
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage People")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingPerson = true
                } label: {
                    Label("Add Person", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingPerson) {
            NavigationStack { NewPersonView() }
        }
        .confirmationDialog(
            "Delete this Person?",
            isPresented: Binding(
                get: { personToDelete != nil },
                set: { if !$0 { personToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Person", role: .destructive) {
                guard let personToDelete, !personToDelete.isSelf else { return }
                do {
                    modelContext.delete(personToDelete)
                    try modelContext.save()
                    self.personToDelete = nil
                } catch {
                    modelContext.rollback()
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their attribution rows will be deleted. Materials will remain.")
        }
        .errorAlert(message: $errorMessage)
    }
}

struct NewPersonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var savesImmediately = true
    var didCreate: ((Person) -> Void)?

    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
        }
        .navigationTitle("New Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        let person = try PersonService.createNonself(name: name, in: modelContext)
                        if savesImmediately {
                            try modelContext.save()
                        }
                        didCreate?(person)
                        dismiss()
                    } catch {
                        if savesImmediately {
                            modelContext.rollback()
                        }
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .errorAlert(message: $errorMessage)
    }
}

private struct PersonTestEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var person: Person
    @State private var draftName = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(person.isSelf ? "Optional actual name" : "Name") {
                TextField("Name", text: $draftName)
            }
            Section("Provenance") {
                LabeledContent("Attributions", value: "\(person.attributions.count)")
                if person.isSelf {
                    Text("This is Zaytun’s stable self identity and cannot be deleted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !person.isSelf {
                Section {
                    Button("Delete Person", role: .destructive) { isDeleting = true }
                }
            }
        }
        .navigationTitle(person.displayName)
        .onAppear { draftName = person.name ?? "" }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try PersonService.rename(person, to: draftName)
                        try modelContext.save()
                    } catch {
                        modelContext.rollback()
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .confirmationDialog("Delete this Person?", isPresented: $isDeleting) {
            Button("Delete Person", role: .destructive) {
                guard !person.isSelf else { return }
                do {
                    modelContext.delete(person)
                    try modelContext.save()
                    dismiss()
                } catch {
                    modelContext.rollback()
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their attribution rows will be deleted. Materials will remain.")
        }
        .errorAlert(message: $errorMessage)
    }
}
