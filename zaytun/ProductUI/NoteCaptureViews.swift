import SwiftData
import SwiftUI

struct QuickNoteCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTextFocused: Bool

    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .padding()
            .focused($isTextFocused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What is worth keeping?")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Quick Note")
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
                    Button("Done") { isTextFocused = false }
                }
            }
            .task { isTextFocused = true }
            .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            _ = try NoteService.quickCapture(text: text, in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

struct FullNoteCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Topic.title) private var topics: [Topic]

    @State private var draft = NoteCaptureDraft()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Note") {
                TextField("Optional title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)
                TextEditor(text: $draft.text)
                    .frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if draft.text.isEmpty {
                            Text("Write your note")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Section {
                TextField("Where did you encounter this?", text: $draft.source)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Source (Optional)")
            } footer: {
                Text("For example: Conversation, Book, Lecture, or Personal thought.")
            }

            TopicSelectionSection(
                topics: topics,
                selectedIDs: $draft.selectedTopicIDs
            )
        }
        .navigationTitle("New Note")
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
        .errorAlert(message: $errorMessage)
    }

    private func save() {
        do {
            let selectedTopics = topics.filter { draft.selectedTopicIDs.contains($0.id) }
            _ = try NoteService.fullCapture(
                title: draft.title,
                text: draft.text,
                source: draft.source,
                topics: selectedTopics,
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

struct TopicSelectionSection: View {
    let topics: [Topic]
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        Section {
            if topics.isEmpty {
                Text("No Topics yet. Create them from Organize.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(topics) { topic in
                    Button {
                        if selectedIDs.contains(topic.id) {
                            selectedIDs.remove(topic.id)
                        } else {
                            selectedIDs.insert(topic.id)
                        }
                    } label: {
                        HStack {
                            Text(topic.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedIDs.contains(topic.id) {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Topics (Optional)")
        } footer: {
            if !topics.isEmpty {
                Text("Choose any intellectual threads this note contributes to.")
            }
        }
    }
}
