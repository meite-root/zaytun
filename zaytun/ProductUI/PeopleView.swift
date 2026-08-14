import SwiftData
import SwiftUI

struct PeopleView: View {
    @Query(sort: \Person.createdAt) private var people: [Person]

    private var selfPeople: [Person] {
        people.filter(\.isSelf)
    }

    private var otherPeople: [Person] {
        people
            .filter { !$0.isSelf }
            .sorted {
                let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
                return nameOrder == .orderedSame
                    ? $0.id.uuidString < $1.id.uuidString
                    : nameOrder == .orderedAscending
            }
    }

    var body: some View {
        List {
            Section("Me") {
                ForEach(selfPeople) { person in
                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        PersonListRow(person: person)
                    }
                }
            }

            Section("Other People") {
                if otherPeople.isEmpty {
                    Text("No other People")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(otherPeople) { person in
                        NavigationLink {
                            PersonDetailView(person: person)
                        } label: {
                            PersonListRow(person: person)
                        }
                    }
                }
            }
        }
        .navigationTitle("People")
    }
}

struct PersonListRow: View {
    let person: Person

    private var materialCount: Int {
        PersonService.materialLinks(for: person).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(person.displayName)
                .font(.headline)
            if person.isSelf, let actualName = person.name?.trimmedNonempty {
                Text(actualName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(materialCount == 1 ? "1 Material" : "\(materialCount) Materials")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PersonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let person: Person

    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var materialLinks: [PersonMaterialLink] {
        PersonService.materialLinks(for: person)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.displayName)
                        .font(.title2.weight(.semibold))
                    if person.isSelf, let actualName = person.name?.trimmedNonempty {
                        Text(actualName)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
            }

            Section("Materials") {
                if materialLinks.isEmpty {
                    Text("No associated Materials")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(materialLinks) { link in
                        NavigationLink {
                            MaterialDetailView(material: link.material)
                        } label: {
                            PersonMaterialRow(link: link)
                        }
                    }
                }
            }

            if person.isSelf {
                Section {
                    Text("This is Zaytun’s stable self identity and is shown as Me in provenance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if person.isSelf {
                    Button("Edit") { isRenaming = true }
                } else {
                    Menu {
                        Button("Rename", systemImage: "pencil") {
                            isRenaming = true
                        }
                        Button("Delete Person", systemImage: "trash", role: .destructive) {
                            isDeleting = true
                        }
                    } label: {
                        Label("Person Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isRenaming) {
            NavigationStack {
                RenamePersonView(person: person)
            }
        }
        .confirmationDialog(
            "Delete \(person.displayName)?",
            isPresented: $isDeleting,
            titleVisibility: .visible
        ) {
            Button("Delete Person", role: .destructive, action: deletePerson)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Materials will remain. Only this Person and their provenance links will be removed.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func deletePerson() {
        do {
            try PersonService.delete(person, from: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct PersonMaterialRow: View {
    let link: PersonMaterialLink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(link.material.displayTitle)
                .font(.headline)
                .lineLimit(2)
            Text(link.roleSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let source = link.material.source?.trimmedNonempty {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct RenamePersonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let person: Person

    @State private var name: String
    @State private var errorMessage: String?

    init(person: Person) {
        self.person = person
        _name = State(initialValue: person.name ?? "")
    }

    var body: some View {
        Form {
            Section(person.isSelf ? "Optional actual name" : "Name") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
            }
            if person.isSelf {
                Section {
                    Text("The provenance alias remains Me.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(person.isSelf ? "Edit My Name" : "Rename Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            try PersonService.rename(person, to: name)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
