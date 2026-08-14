import Foundation
import SwiftData
import SwiftUI

private enum MaterialAssociationError: LocalizedError {
    case missingPerson

    var errorDescription: String? {
        String(localized: "The selected Person is no longer available.")
    }
}

struct AddTopicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Topic.title) private var topics: [Topic]

    let material: Material
    let didFinish: () -> Void

    @State private var searchText = ""
    @State private var isCreatingTopic = false
    @State private var errorMessage: String?

    private var filteredTopics: [Topic] {
        guard let query = searchText.trimmedNonempty else { return topics }
        return topics.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section("Existing Topics") {
                if filteredTopics.isEmpty {
                    Text(searchText.isEmpty ? "No Topics yet" : "No matching Topics")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredTopics) { topic in
                        let isAssigned = material.topics.contains { $0.id == topic.id }
                        Button {
                            assign(topic)
                        } label: {
                            HStack {
                                Text(topic.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isAssigned {
                                    Label("Assigned", systemImage: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAssigned)
                    }
                }
            }

            Section {
                Button {
                    isCreatingTopic = true
                } label: {
                    Label("Create New Topic", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Add Topic")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find a Topic")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $isCreatingTopic) {
            NavigationStack {
                NewAssignedTopicView(material: material, didFinish: didFinish)
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func assign(_ topic: Topic) {
        do {
            TopicService.assign(topic, to: material)
            try modelContext.save()
            didFinish()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewAssignedTopicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let material: Material
    let didFinish: () -> Void

    @State private var title = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Topic name", text: $title)
                .textInputAutocapitalization(.words)
        }
        .navigationTitle("New Topic")
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
            _ = try TopicService.createAndAssign(
                title: title,
                to: material,
                in: modelContext
            )
            try modelContext.save()
            didFinish()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct AddAttributionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.createdAt) private var people: [Person]

    let material: Material
    let didFinish: () -> Void

    @State private var selectedPersonID: UUID?
    @State private var pendingPersonName: String?
    @State private var role: AttributionRole = .createdBy
    @State private var isCreatingPerson = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Person") {
                Picker("Person", selection: $selectedPersonID) {
                    Text("Select a Person").tag(UUID?.none)
                    ForEach(people) { person in
                        Text(person.displayName).tag(Optional(person.id))
                    }
                }
                .onChange(of: selectedPersonID) {
                    if selectedPersonID != nil {
                        pendingPersonName = nil
                    }
                }

                if let pendingPersonName {
                    LabeledContent("New Person", value: pendingPersonName)
                }

                Button {
                    isCreatingPerson = true
                } label: {
                    Label("Create Person", systemImage: "person.badge.plus")
                }
            }

            Section("Role") {
                Picker("Role", selection: $role) {
                    ForEach(AttributionRole.supported) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("Add Attribution")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(selectedPersonID == nil && pendingPersonName == nil)
            }
        }
        .sheet(isPresented: $isCreatingPerson) {
            NavigationStack {
                NewAttributionPersonDraftView { name in
                    pendingPersonName = name
                    selectedPersonID = nil
                }
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            if let pendingPersonName {
                try AttributionService.create(
                    material: material,
                    newPersonNamed: pendingPersonName,
                    role: role,
                    in: modelContext
                )
            } else if let selectedPersonID,
                      let person = people.first(where: { $0.id == selectedPersonID }) {
                try AttributionService.create(
                    material: material,
                    person: person,
                    role: role,
                    in: modelContext
                )
            } else {
                throw MaterialAssociationError.missingPerson
            }
            try modelContext.save()
            didFinish()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewAttributionPersonDraftView: View {
    @Environment(\.dismiss) private var dismiss
    let didValidate: (String) -> Void

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
                Button("Continue", action: validate)
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func validate() {
        do {
            didValidate(try PersonService.validatedNonselfName(name))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
