import SwiftData
import SwiftUI

struct MaterialDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let material: Material

    @State private var isEditing = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if let title = material.title?.trimmedNonempty {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .listRowSeparator(.hidden)
                }
                if let text = material.text?.trimmedNonempty {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .listRowSeparator(.hidden)
                } else if material.type != .note {
                    ContentUnavailableView(
                        material.type?.displayName ?? "Material",
                        systemImage: "doc"
                    )
                }
            }

            if let source = material.source?.trimmedNonempty {
                Section("Source") {
                    Text(source)
                }
            }

            Section("Topics") {
                if material.topics.isEmpty {
                    Text("No Topics")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(material.topics.sorted { $0.title < $1.title }) { topic in
                        Text(topic.title)
                    }
                }
            }

            if !material.attributions.isEmpty {
                Section("Provenance") {
                    ForEach(material.attributions.sorted { $0.createdAt < $1.createdAt }) { attribution in
                        LabeledContent(
                            attribution.role.displayName,
                            value: attribution.person.displayName
                        )
                    }
                }
            }

            Section("Details") {
                LabeledContent("Status", value: material.status?.displayName ?? "Unsupported")
                LabeledContent("Captured") {
                    Text(material.capturedAt, format: .dateTime.day().month().year().hour().minute())
                }
            }

            Section {
                Button {
                    changeStatus()
                } label: {
                    Label(
                        material.status == .inbox ? "Mark Organized" : "Return to Inbox",
                        systemImage: material.status == .inbox ? "checkmark.circle" : "tray.and.arrow.down"
                    )
                }

                Button("Delete Material", systemImage: "trash", role: .destructive) {
                    isDeleting = true
                }
            }
        }
        .navigationTitle(material.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if material.type == .note {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                NoteEditorView(material: material)
            }
        }
        .confirmationDialog("Delete this Material?", isPresented: $isDeleting) {
            Button("Delete Material", role: .destructive, action: deleteMaterial)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its provenance statements will be removed. People and Topics will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func changeStatus() {
        let newStatus: MaterialStatus = material.status == .inbox ? .organized : .inbox
        do {
            NoteService.setStatus(newStatus, for: material)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func deleteMaterial() {
        do {
            modelContext.delete(material)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct NoteEditDraft {
    var title: String
    var text: String
    var source: String
}

private struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let material: Material

    @State private var draft: NoteEditDraft
    @State private var isAddingTopic = false
    @State private var isAddingAttribution = false
    @State private var attributionToRemove: MaterialAttribution?
    @State private var errorMessage: String?

    init(material: Material) {
        self.material = material
        _draft = State(initialValue: NoteEditDraft(
            title: material.title ?? "",
            text: material.text ?? "",
            source: material.source ?? ""
        ))
    }

    var body: some View {
        Form {
            Section("Note") {
                TextField("Optional title", text: $draft.title)
                TextEditor(text: $draft.text)
                    .frame(minHeight: 180)
            }
            Section("Source (Optional)") {
                TextField("Where did you encounter this?", text: $draft.source)
            }

            Section("Topics") {
                if material.topics.isEmpty {
                    Text("No Topics assigned")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(material.topics.sorted { $0.title < $1.title }) { topic in
                        Text(topic.title)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    remove(topic)
                                }
                            }
                    }
                }

                Button {
                    isAddingTopic = true
                } label: {
                    Label("Add Topic", systemImage: "plus")
                }
            }

            Section("Provenance") {
                if material.attributions.isEmpty {
                    Text("No Person attribution")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(material.attributions.sorted { $0.createdAt < $1.createdAt }) { attribution in
                        HStack {
                            Text(attribution.person.displayName)
                            Spacer()
                            Menu(attribution.role.displayName) {
                                ForEach(AttributionRole.supported) { role in
                                    Button(role.displayName) {
                                        update(attribution, to: role)
                                    }
                                }
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                attributionToRemove = attribution
                            }
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
        .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $isAddingTopic) {
            NavigationStack {
                AddTopicView(material: material) {
                    isAddingTopic = false
                }
            }
        }
        .sheet(isPresented: $isAddingAttribution) {
            NavigationStack {
                AddAttributionView(material: material) {
                    isAddingAttribution = false
                }
            }
        }
        .confirmationDialog(
            "Remove this attribution?",
            isPresented: Binding(
                get: { attributionToRemove != nil },
                set: { if !$0 { attributionToRemove = nil } }
            )
        ) {
            Button("Remove Attribution", role: .destructive, action: removeAttribution)
            Button("Cancel", role: .cancel) { attributionToRemove = nil }
        } message: {
            Text("The Material and Person will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            try NoteService.update(
                material,
                title: draft.title,
                text: draft.text,
                source: draft.source,
                topics: material.topics
            )
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ topic: Topic) {
        do {
            TopicService.remove(topic, from: material)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func update(
        _ attribution: MaterialAttribution,
        to role: AttributionRole
    ) {
        do {
            try AttributionService.updateRole(of: attribution, to: role)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func removeAttribution() {
        guard let attributionToRemove else { return }
        do {
            AttributionService.remove(attributionToRemove, from: modelContext)
            try modelContext.save()
            self.attributionToRemove = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
