import SwiftData
import SwiftUI

struct ReflectionRow: View {
    let reflection: Reflection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ReflectionService.displayName(for: reflection))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(reflection.body)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

struct ReflectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let reflection: Reflection

    @State private var isEditing = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var materials: [Material] {
        ReflectionService.materials(for: reflection)
    }

    private var topics: [Topic] {
        ReflectionService.topics(for: reflection)
    }

    var body: some View {
        List {
            Section {
                Text(ReflectionService.displayName(for: reflection))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                Text(reflection.body)
                    .font(.title3)
                    .textSelection(.enabled)
                    .listRowSeparator(.hidden)
            }

            Section("Materials") {
                if materials.isEmpty {
                    Text("No related Materials")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(materials) { material in
                        NavigationLink {
                            MaterialDetailView(material: material)
                        } label: {
                            ProductMaterialRow(material: material)
                        }
                    }
                }
            }

            Section("Topics") {
                if topics.isEmpty {
                    Text("No related Topics")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topics) { topic in
                        NavigationLink {
                            TopicEditorView(topic: topic)
                        } label: {
                            Text(topic.title)
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Created") {
                    Text(
                        reflection.createdAt,
                        format: .dateTime.day().month().year().hour().minute()
                    )
                }
                LabeledContent("Updated") {
                    Text(
                        reflection.updatedAt,
                        format: .dateTime.day().month().year().hour().minute()
                    )
                }
            }
        }
        .navigationTitle(ReflectionService.displayName(for: reflection))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Reflection", systemImage: "pencil") {
                        isEditing = true
                    }
                    Button("Delete Reflection", systemImage: "trash", role: .destructive) {
                        isDeleting = true
                    }
                } label: {
                    Label("Reflection Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                ReflectionEditorView(reflection: reflection)
            }
        }
        .confirmationDialog(
            "Delete this Reflection?",
            isPresented: $isDeleting,
            titleVisibility: .visible
        ) {
            Button("Delete Reflection", role: .destructive, action: deleteReflection)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its Materials and Topics will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func deleteReflection() {
        do {
            ReflectionService.delete(reflection, from: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct ReflectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Material.capturedAt, order: .reverse) private var materials: [Material]
    @Query(sort: \Topic.title) private var topics: [Topic]
    @FocusState private var isBodyFocused: Bool

    private let reflection: Reflection?

    @State private var draft: ReflectionDraft
    @State private var errorMessage: String?

    private var selectedMaterials: [Material] {
        materials.filter { draft.selectedMaterialIDs.contains($0.id) }
    }

    private var selectedTopics: [Topic] {
        topics.filter { draft.selectedTopicIDs.contains($0.id) }
    }

    init() {
        reflection = nil
        _draft = State(initialValue: ReflectionDraft())
    }

    init(material: Material) {
        reflection = nil
        _draft = State(initialValue: ReflectionDraft(
            selectedMaterialIDs: [material.id]
        ))
    }

    init(topic: Topic) {
        reflection = nil
        _draft = State(initialValue: ReflectionDraft(
            selectedTopicIDs: [topic.id]
        ))
    }

    init(reflection: Reflection) {
        self.reflection = reflection
        _draft = State(initialValue: ReflectionDraft(reflection: reflection))
    }

    var body: some View {
        Form {
            Section("Type") {
                Picker("Reflection type", selection: $draft.kindRawValue) {
                    if ReflectionKind(rawValue: draft.kindRawValue) == nil {
                        Text("Unsupported").tag(draft.kindRawValue)
                    }
                    ForEach(ReflectionKind.allCases) { kind in
                        Text(kind.displayName).tag(kind.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Reflection") {
                TextEditor(text: $draft.body)
                    .frame(minHeight: 220)
                    .focused($isBodyFocused)
                    .overlay(alignment: .topLeading) {
                        if draft.body.isEmpty {
                            Text("What are you thinking?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Section("Materials") {
                if selectedMaterials.isEmpty {
                    Text("No Materials attached")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedMaterials) { material in
                        ProductMaterialRow(material: material)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    draft.selectedMaterialIDs.remove(material.id)
                                }
                            }
                    }
                }

                NavigationLink {
                    ReflectionMaterialPickerView(
                        selectedIDs: $draft.selectedMaterialIDs
                    )
                } label: {
                    Label("Add Material", systemImage: "plus")
                }
            }

            Section("Topics") {
                if selectedTopics.isEmpty {
                    Text("No Topics attached")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedTopics) { topic in
                        Text(topic.title)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    draft.selectedTopicIDs.remove(topic.id)
                                }
                            }
                    }
                }

                ForEach(draft.pendingTopics) { pendingTopic in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pendingTopic.title)
                        Text("New Topic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            draft.pendingTopics.removeAll { $0.id == pendingTopic.id }
                        }
                    }
                }

                NavigationLink {
                    ReflectionTopicPickerView(
                        selectedIDs: $draft.selectedTopicIDs,
                        pendingTopics: $draft.pendingTopics
                    )
                } label: {
                    Label("Add Topic", systemImage: "plus")
                }
            }
        }
        .navigationTitle(reflection == nil ? "New Reflection" : "Edit Reflection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isBodyFocused = false }
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            _ = try ReflectionService.validatedBody(draft.body)
            let selectedMaterials = materials.filter {
                draft.selectedMaterialIDs.contains($0.id)
            }
            var selectedTopics = topics.filter {
                draft.selectedTopicIDs.contains($0.id)
            }
            for pendingTopic in draft.pendingTopics {
                selectedTopics.append(try TopicService.create(
                    title: pendingTopic.title,
                    in: modelContext
                ))
            }

            if let reflection {
                try ReflectionService.update(
                    reflection,
                    body: draft.body,
                    kindRawValue: draft.kindRawValue,
                    materials: selectedMaterials,
                    topics: selectedTopics
                )
            } else {
                guard let kind = ReflectionKind(rawValue: draft.kindRawValue) else {
                    throw ReflectionValidationError.unsupportedKind
                }
                try ReflectionService.create(
                    body: draft.body,
                    kind: kind,
                    materials: selectedMaterials,
                    topics: selectedTopics,
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

private struct ReflectionMaterialPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Material.capturedAt, order: .reverse) private var materials: [Material]

    @Binding var selectedIDs: Set<UUID>
    @State private var searchText = ""

    private var filteredMaterials: [Material] {
        guard let query = searchText.trimmedNonempty else { return materials }
        return materials.filter {
            $0.title?.localizedCaseInsensitiveContains(query) == true
                || $0.text?.localizedCaseInsensitiveContains(query) == true
                || $0.source?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        List {
            if filteredMaterials.isEmpty {
                Text(searchText.isEmpty ? "No Materials yet" : "No matching Materials")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredMaterials) { material in
                    Button {
                        toggle(material.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ProductMaterialRow(material: material)
                            if selectedIDs.contains(material.id) {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add Material")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find a Material")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

private struct ReflectionTopicPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Topic.title) private var topics: [Topic]

    @Binding var selectedIDs: Set<UUID>
    @Binding var pendingTopics: [PendingReflectionTopic]
    @State private var searchText = ""
    @State private var isCreatingTopic = false

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
                        Button {
                            toggle(topic.id)
                        } label: {
                            HStack {
                                Text(topic.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedIDs.contains(topic.id) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $isCreatingTopic) {
            NavigationStack {
                NewReflectionTopicDraftView { title in
                    pendingTopics.append(PendingReflectionTopic(title: title))
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

private struct NewReflectionTopicDraftView: View {
    @Environment(\.dismiss) private var dismiss
    let didValidate: (String) -> Void

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
                Button("Add", action: validate)
            }
        }
        .errorAlert(message: $errorMessage)
    }

    private func validate() {
        do {
            didValidate(try TopicService.validatedTitle(title))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
