import SwiftData
import SwiftUI

struct TopicsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Topic.title) private var topics: [Topic]

    @State private var isAddingTopic = false
    @State private var topicToDelete: Topic?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if topics.isEmpty {
                ContentUnavailableView(
                    "No Topics",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Create a living intellectual thread for your Materials.")
                )
            } else {
                List(topics) { topic in
                    NavigationLink {
                        TopicEditorView(topic: topic)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.headline)
                            HStack(spacing: 8) {
                                let materialCount = TopicService.materials(for: topic).count
                                Text(materialCount == 1 ? "1 Material" : "\(materialCount) Materials")
                                if !topic.disciplines.isEmpty {
                                    Text("·")
                                    Text(topic.disciplines.map(\.name).sorted().joined(separator: ", "))
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { topicToDelete = topic }
                    }
                }
            }
        }
        .navigationTitle("Topics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingTopic = true
                } label: {
                    Label("New Topic", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingTopic) {
            NavigationStack { NewTopicView() }
        }
        .confirmationDialog(
            "Delete this Topic?",
            isPresented: Binding(
                get: { topicToDelete != nil },
                set: { if !$0 { topicToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Topic", role: .destructive, action: deleteTopic)
            Button("Cancel", role: .cancel) { topicToDelete = nil }
        } message: {
            Text("Materials, Reflections, and Disciplines will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func deleteTopic() {
        guard let topicToDelete else { return }
        do {
            TopicService.delete(topicToDelete, from: modelContext)
            try modelContext.save()
            self.topicToDelete = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct NewTopicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
            _ = try TopicService.create(title: title, in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct TopicEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Discipline.name) private var disciplines: [Discipline]
    let topic: Topic

    @State private var title: String
    @State private var selectedDisciplineIDs: Set<UUID>
    @State private var isAddingReflection = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var materials: [Material] {
        TopicService.materials(for: topic)
    }

    private var reflections: [Reflection] {
        ReflectionService.reflections(for: topic)
    }

    init(topic: Topic) {
        self.topic = topic
        _title = State(initialValue: topic.title)
        _selectedDisciplineIDs = State(initialValue: Set(topic.disciplines.map(\.id)))
    }

    var body: some View {
        Form {
            Section("Topic") {
                TextField("Topic name", text: $title)
            }

            Section("Disciplines") {
                if disciplines.isEmpty {
                    Text("No Disciplines yet. Create one from Organize.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(disciplines) { discipline in
                        Button {
                            toggle(discipline.id)
                        } label: {
                            HStack {
                                Text(discipline.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedDisciplineIDs.contains(discipline.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Materials") {
                if materials.isEmpty {
                    Text("No Materials yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(materials) { material in
                        NavigationLink {
                            MaterialDetailView(material: material)
                        } label: {
                            TopicMaterialRow(material: material)
                        }
                    }
                }
            }

            Section("Reflections") {
                if reflections.isEmpty {
                    Text("No Reflections yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reflections) { reflection in
                        NavigationLink {
                            ReflectionDetailView(reflection: reflection)
                        } label: {
                            ReflectionRow(reflection: reflection)
                        }
                    }
                }

                Button {
                    isAddingReflection = true
                } label: {
                    Label("Add Reflection", systemImage: "plus")
                }
            }

            Section {
                Button("Delete Topic", role: .destructive) { isDeleting = true }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .sheet(isPresented: $isAddingReflection) {
            NavigationStack {
                ReflectionEditorView(topic: topic)
            }
        }
        .confirmationDialog("Delete this Topic?", isPresented: $isDeleting) {
            Button("Delete Topic", role: .destructive, action: deleteTopic)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Materials, Reflections, and Disciplines will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func toggle(_ id: UUID) {
        if selectedDisciplineIDs.contains(id) {
            selectedDisciplineIDs.remove(id)
        } else {
            selectedDisciplineIDs.insert(id)
        }
    }

    private func save() {
        do {
            try TopicService.update(
                topic,
                title: title,
                disciplines: disciplines.filter { selectedDisciplineIDs.contains($0.id) }
            )
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTopic() {
        do {
            TopicService.delete(topic, from: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct TopicMaterialRow: View {
    let material: Material

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(material.displayTitle)
                .font(.headline)
                .lineLimit(2)

            if material.title?.trimmedNonempty != nil,
               let text = material.text?.trimmedNonempty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let source = material.source?.trimmedNonempty {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let materialType = material.type {
                Text(materialType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
