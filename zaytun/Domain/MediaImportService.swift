import Foundation
import SwiftData
import UniformTypeIdentifiers

enum MediaImportError: LocalizedError, Equatable {
    case unsupportedContentType(String)
    case invalidMaterialType

    var errorDescription: String? {
        switch self {
        case .unsupportedContentType:
            "Select an image, audio, or video file."
        case .invalidMaterialType:
            "Zaytun could not determine this media Material's type."
        }
    }
}

extension SharedMediaKind {
    var materialType: MaterialType {
        switch self {
        case .image: .image
        case .audio: .audio
        case .video: .video
        }
    }
}

@MainActor
enum MediaImportService {
    typealias SaveAction = (ModelContext) throws -> Void

    @discardableResult
    static func importMedia(
        from sourceURL: URL,
        contentType: UTType,
        originalFilename: String? = nil,
        materialID: UUID = UUID(),
        title: String? = nil,
        source: String? = nil,
        topics: [Topic] = [],
        now: Date = .now,
        replaceExistingFile: Bool = false,
        storage: MediaStorageService,
        in context: ModelContext,
        save: SaveAction? = nil
    ) throws -> Material {
        guard let mediaKind = SharedMediaKind.detect(contentType: contentType) else {
            throw MediaImportError.unsupportedContentType(contentType.identifier)
        }

        let normalizedTopics = unique(topics)
        let storedFilename = try storage.copyIntoStorage(
            from: sourceURL,
            materialID: materialID,
            contentType: contentType,
            originalFilename: originalFilename,
            replaceExisting: replaceExistingFile
        )

        let material = Material(
            id: materialID,
            type: mediaKind.materialType,
            status: MaterialOrganizationService.expectedStatus(forTopics: normalizedTopics),
            title: title?.trimmedNonempty,
            mediaFilename: storedFilename,
            contentTypeIdentifier: contentType.identifier,
            createdAt: now,
            updatedAt: now,
            capturedAt: now,
            source: source?.trimmedNonempty,
            lastReviewedAt: nil,
            nextReviewAt: now,
            reviewCount: 0,
            isArchived: false,
            topics: normalizedTopics
        )
        context.insert(material)

        do {
            if let save {
                try save(context)
            } else {
                try context.save()
            }
            return material
        } catch {
            context.rollback()
            try? storage.removeFile(named: storedFilename)
            throw error
        }
    }

    static func updateMetadata(
        _ material: Material,
        title: String,
        source: String,
        topics: [Topic],
        now: Date = .now
    ) throws {
        guard material.type != nil, material.type != .note else {
            throw MediaImportError.invalidMaterialType
        }
        let normalizedTitle = title.trimmedNonempty
        let normalizedSource = source.trimmedNonempty
        let normalizedTopics = unique(topics)
        let changed = material.title != normalizedTitle
            || material.source != normalizedSource
            || Set(material.topics.map(\.id)) != Set(normalizedTopics.map(\.id))
        if changed {
            material.title = normalizedTitle
            material.source = normalizedSource
            material.topics = normalizedTopics
            material.updatedAt = now
        }
        MaterialOrganizationService.synchronizeStatus(for: material)
    }

    static func delete(
        _ material: Material,
        storage: MediaStorageService,
        from context: ModelContext
    ) throws {
        let deletion = try storage.stageDeletion(of: material.mediaFilename)
        context.delete(material)
        do {
            try context.save()
        } catch {
            context.rollback()
            if let deletion {
                try? storage.restoreDeletion(deletion)
            }
            throw error
        }
        if let deletion {
            try storage.commitDeletion(deletion)
        }
    }

    private static func unique(_ topics: [Topic]) -> [Topic] {
        var ids: Set<UUID> = []
        return topics.filter { ids.insert($0.id).inserted }
    }
}

struct MediaQueueIngestionFailure: Equatable {
    let importID: UUID
    let message: String
}

struct MediaQueueIngestionResult: Equatable {
    let importedCount: Int
    let alreadyImportedCount: Int
    let failures: [MediaQueueIngestionFailure]
}

@MainActor
enum SharedMediaIngestionService {
    static func ingestPending(
        queue: SharedImportQueue,
        storage: MediaStorageService,
        in context: ModelContext,
        onImported: ((Material) -> Void)? = nil
    ) throws -> MediaQueueIngestionResult {
        let entries = try queue.entries()
        let existingMaterials = try context.fetch(FetchDescriptor<Material>())
        var existingIDs = Set(existingMaterials.map(\.id))
        var importedCount = 0
        var alreadyImportedCount = 0
        var failures: [MediaQueueIngestionFailure] = []

        for entry in entries {
            let importID = entry.manifest.importID
            if existingIDs.contains(importID) {
                try queue.remove(entry)
                alreadyImportedCount += 1
                continue
            }

            do {
                guard let contentType = UTType(entry.manifest.contentTypeIdentifier) else {
                    throw MediaImportError.unsupportedContentType(
                        entry.manifest.contentTypeIdentifier
                    )
                }
                let material = try MediaImportService.importMedia(
                    from: entry.payloadURL,
                    contentType: contentType,
                    originalFilename: entry.manifest.originalFilename,
                    materialID: importID,
                    now: entry.manifest.createdAt,
                    replaceExistingFile: true,
                    storage: storage,
                    in: context
                )
                existingIDs.insert(importID)
                try queue.remove(entry)
                importedCount += 1
                onImported?(material)
            } catch {
                failures.append(MediaQueueIngestionFailure(
                    importID: importID,
                    message: error.localizedDescription
                ))
            }
        }

        return MediaQueueIngestionResult(
            importedCount: importedCount,
            alreadyImportedCount: alreadyImportedCount,
            failures: failures
        )
    }
}
