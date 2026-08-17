import CoreTransferable
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

fileprivate struct MediaSelection: Identifiable {
    let id = UUID()
    let temporaryURL: URL
    let contentType: UTType
    let originalFilename: String?
}

private struct MediaPickerFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try MediaSelectionStaging.copyToTemporary(received.file)
                .map(MediaPickerFile.init(url:))
                .get()
        }
        FileRepresentation(importedContentType: .movie) { received in
            try MediaSelectionStaging.copyToTemporary(received.file)
                .map(MediaPickerFile.init(url:))
                .get()
        }
    }
}

enum MediaSelectionStaging {
    nonisolated static func copyToTemporary(_ sourceURL: URL) -> Result<URL, Error> {
        Result {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "ZaytunMediaSelections", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let pathExtension = sourceURL.pathExtension
            let filename = pathExtension.isEmpty
                ? UUID().uuidString
                : "\(UUID().uuidString).\(pathExtension.lowercased())"
            let destination = directory.appending(path: filename)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        }
    }

    fileprivate static func remove(_ selection: MediaSelection?) {
        guard let selection else { return }
        removeTemporaryFile(at: selection.temporaryURL)
    }

    nonisolated static func removeTemporaryFile(
        at temporaryURL: URL?,
        fileManager: FileManager = .default
    ) {
        guard let temporaryURL else { return }
        try? fileManager.removeItem(at: temporaryURL)
    }
}

struct MediaImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Topic.title) private var topics: [Topic]

    @State private var photoItem: PhotosPickerItem?
    @State private var selection: MediaSelection?
    @State private var title = ""
    @State private var source = ""
    @State private var selectedTopicIDs: Set<UUID> = []
    @State private var isChoosingFile = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let selection {
                Section("Selected Media") {
                    Label(
                        selection.contentType.localizedDescription ?? selection.contentType.identifier,
                        systemImage: systemImage(for: selection.contentType)
                    )
                    if let originalFilename = selection.originalFilename {
                        Text(originalFilename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Details (Optional)") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Where did you encounter this?", text: $source)
                        .textInputAutocapitalization(.words)
                }

                TopicSelectionSection(
                    topics: topics,
                    selectedIDs: $selectedTopicIDs
                )

                Section {
                    Button("Choose Different Media", systemImage: "arrow.triangle.2.circlepath") {
                        clearSelection()
                    }
                }
            } else {
                Section("Choose Media") {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        Label("Photo or Video", systemImage: "photo.on.rectangle.angled")
                    }

                    Button {
                        isChoosingFile = true
                    } label: {
                        Label("Audio or Media File", systemImage: "folder")
                    }
                }

                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Preparing media…")
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Media")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            if selection != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task { await loadPhotoItem(photoItem) }
        }
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.image, .audio, .movie, .audiovisualContent],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
        .onDisappear {
            MediaSelectionStaging.remove(selection)
        }
        .interactiveDismissDisabled(isLoading)
        .errorAlert(message: $errorMessage)
    }

    @MainActor
    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let contentType = item.supportedContentTypes.first(where: {
                SharedMediaKind.detect(contentType: $0) != nil
            }) else {
                throw MediaImportError.unsupportedContentType("Photos selection")
            }
            guard let transferred = try await item.loadTransferable(type: MediaPickerFile.self) else {
                throw MediaStorageError.missingSource
            }
            replaceSelection(MediaSelection(
                temporaryURL: transferred.url,
                contentType: contentType,
                originalFilename: nil
            ))
        } catch {
            errorMessage = error.localizedDescription
            self.photoItem = nil
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        do {
            let sourceURL = try result.get().first ?? { throw MediaStorageError.missingSource }()
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            let resourceValues = try sourceURL.resourceValues(forKeys: [.contentTypeKey])
            let contentType = resourceValues.contentType
                ?? UTType(filenameExtension: sourceURL.pathExtension)
            guard let contentType,
                  SharedMediaKind.detect(contentType: contentType) != nil else {
                throw MediaImportError.unsupportedContentType(
                    contentType?.identifier ?? sourceURL.pathExtension
                )
            }
            let temporaryURL = try MediaSelectionStaging.copyToTemporary(sourceURL).get()
            replaceSelection(MediaSelection(
                temporaryURL: temporaryURL,
                contentType: contentType,
                originalFilename: sourceURL.lastPathComponent
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let selection else { return }
        do {
            let storage = try MediaStorageService.applicationSupport()
            let selectedTopics = topics.filter { selectedTopicIDs.contains($0.id) }
            _ = try MediaImportService.importMedia(
                from: selection.temporaryURL,
                contentType: selection.contentType,
                originalFilename: selection.originalFilename,
                title: title,
                source: source,
                topics: selectedTopics,
                storage: storage,
                in: modelContext
            )
            MediaSelectionStaging.remove(selection)
            self.selection = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() {
        clearSelection()
        dismiss()
    }

    private func clearSelection() {
        MediaSelectionStaging.remove(selection)
        selection = nil
        photoItem = nil
    }

    private func replaceSelection(_ newSelection: MediaSelection) {
        MediaSelectionStaging.remove(selection)
        selection = newSelection
    }

    private func systemImage(for contentType: UTType) -> String {
        switch SharedMediaKind.detect(contentType: contentType) {
        case .image: "photo"
        case .audio: "waveform"
        case .video: "video"
        case .none: "doc"
        }
    }
}
