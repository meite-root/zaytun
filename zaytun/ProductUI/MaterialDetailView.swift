import SwiftData
import SwiftUI

struct MaterialDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let material: Material

    @State private var isEditing = false
    @State private var isAddingReflection = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var reflections: [Reflection] {
        ReflectionService.reflections(for: material)
    }

    var body: some View {
        List {
            Section {
                if let title = material.title?.trimmedNonempty {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .listRowSeparator(.hidden)
                }
                if material.type == .note,
                   let text = material.text?.trimmedNonempty {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .listRowSeparator(.hidden)
                } else if material.type != .note {
                    MediaContentView(material: material, videoHeight: 320)
                        .listRowSeparator(.hidden)
                }
            }

            if material.type == .image
                || material.type == .audio
                || material.type == .video {
                MaterialUnderstandingSection(material: material)
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
                    ForEach(AttributionService.ordered(material.attributions)) { attribution in
                        NavigationLink {
                            PersonDetailView(person: attribution.person)
                        } label: {
                            LabeledContent(
                                attribution.role.displayName,
                                value: attribution.person.displayName
                            )
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

            Section("Details") {
                LabeledContent("Status", value: material.status?.displayName ?? "Unsupported")
                LabeledContent("Captured") {
                    Text(material.capturedAt, format: .dateTime.day().month().year().hour().minute())
                }
                if let nextReviewAt = material.nextReviewAt {
                    LabeledContent("Scheduled") {
                        Text(nextReviewAt, format: .dateTime.day().month().year())
                    }
                }
                if let lastReviewedAt = material.lastReviewedAt {
                    LabeledContent("Last Reviewed") {
                        Text(lastReviewedAt, format: .dateTime.day().month().year())
                    }
                }
                if material.reviewCount > 0 {
                    LabeledContent("Reviews", value: "\(material.reviewCount)")
                }
            }

            Section {
                Button("Delete Material", systemImage: "trash", role: .destructive) {
                    isDeleting = true
                }
            }
        }
        .navigationTitle(material.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if material.type != nil {
                    Button("Edit") { isEditing = true }
                }
                MaterialResurfacingMenu(material: material)
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                MaterialEditorView(material: material)
            }
        }
        .sheet(isPresented: $isAddingReflection) {
            NavigationStack {
                ReflectionEditorView(material: material)
            }
        }
        .confirmationDialog("Delete this Material?", isPresented: $isDeleting) {
            Button("Delete Material", role: .destructive, action: deleteMaterial)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its provenance statements will be removed. People, Topics, and Reflections will remain.")
        }
        .errorAlert(message: $errorMessage)
    }

    private func deleteMaterial() {
        do {
            if material.type != .note, material.mediaFilename != nil {
                try MediaImportService.delete(
                    material,
                    storage: try MediaStorageService.applicationSupport(),
                    from: modelContext
                )
            } else {
                modelContext.delete(material)
                try modelContext.save()
            }
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private enum MediaUnderstandingViewState: Equatable {
    case idle
    case processing
    case success
    case failed(String)
}

private struct MaterialUnderstandingSection: View {
    @Environment(\.modelContext) private var modelContext

    let material: Material

    @State private var state: MediaUnderstandingViewState = .idle
    @State private var processingTask: Task<Void, Never>?

    private var extractedText: String? {
        material.extractedText?.trimmedNonempty
    }

    private var heading: String {
        material.type == .image ? "Recognized Text" : "Transcript"
    }

    private var emptyMessage: String {
        material.type == .image ? "No text detected." : "No transcript yet."
    }

    private var actionTitle: String {
        switch material.type {
        case .image:
            extractedText == nil ? "Recognize Text" : "Recognize Text Again"
        case .audio, .video:
            extractedText == nil ? "Transcribe" : "Transcribe Again"
        case .note, .none:
            "Unavailable"
        }
    }

    var body: some View {
        Section(heading) {
            if let extractedText {
                Text(extractedText)
                    .textSelection(.enabled)
            } else {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            }

            switch state {
            case .processing:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(material.type == .image ? "Recognizing text…" : "Transcribing…")
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", role: .cancel) {
                    processingTask?.cancel()
                }
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                actionButton
            case .idle, .success:
                actionButton
            }
        }
        .onDisappear {
            processingTask?.cancel()
            processingTask = nil
        }
    }

    private var actionButton: some View {
        Button(actionTitle, systemImage: material.type == .image ? "text.viewfinder" : "waveform") {
            startProcessing()
        }
        .disabled(state == .processing)
    }

    private func startProcessing() {
        guard state != .processing else { return }
        processingTask?.cancel()
        state = .processing
        processingTask = Task { @MainActor in
            do {
                if material.type == .audio || material.type == .video {
                    switch await MediaUnderstandingService.requestSpeechAuthorization() {
                    case .authorized:
                        break
                    case .denied:
                        throw MediaUnderstandingError.speechPermissionDenied
                    case .restricted:
                        throw MediaUnderstandingError.speechPermissionRestricted
                    case .unavailable:
                        throw MediaUnderstandingError.transcriptionUnavailable
                    }
                }

                _ = try await MediaUnderstandingService.process(
                    material,
                    storage: try MediaStorageService.applicationSupport(),
                    in: modelContext
                )
                state = .success
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(
                    (error as? LocalizedError)?.errorDescription
                        ?? (material.type == .image
                            ? "Text recognition failed. Try again."
                            : "Transcription is unavailable. Try again later.")
                )
            }
        }
    }
}

private struct MaterialEditDraft {
    var title: String
    var text: String
    var source: String
}

private struct MaterialEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let material: Material

    @State private var draft: MaterialEditDraft
    @State private var isAddingTopic = false
    @State private var isAddingAttribution = false
    @State private var attributionToRemove: MaterialAttribution?
    @State private var errorMessage: String?

    init(material: Material) {
        self.material = material
        _draft = State(initialValue: MaterialEditDraft(
            title: material.title ?? "",
            text: material.text ?? "",
            source: material.source ?? ""
        ))
    }

    var body: some View {
        Form {
            Section(material.type == .note ? "Note" : "Material") {
                TextField("Optional title", text: $draft.title)
                if material.type == .note {
                    TextEditor(text: $draft.text)
                        .frame(minHeight: 180)
                }
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
                    ForEach(AttributionService.ordered(material.attributions)) { attribution in
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
        .navigationTitle(material.type == .note ? "Edit Note" : "Edit Media")
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
            if material.type == .note {
                try NoteService.update(
                    material,
                    title: draft.title,
                    text: draft.text,
                    source: draft.source,
                    topics: material.topics
                )
            } else {
                try MediaImportService.updateMetadata(
                    material,
                    title: draft.title,
                    source: draft.source,
                    topics: material.topics
                )
            }
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
