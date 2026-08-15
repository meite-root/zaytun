import Foundation
import SwiftData

struct NoteCaptureDraft {
    var title = ""
    var text = ""
    var source = ""
    var selectedTopicIDs: Set<UUID> = []
}

enum NoteValidationError: LocalizedError, Equatable {
    case emptyText

    var errorDescription: String? {
        switch self {
        case .emptyText:
            String(localized: "Write something before saving this note.")
        }
    }
}

@MainActor
enum NoteService {
    @discardableResult
    static func quickCapture(
        text: String,
        now: Date = .now,
        in context: ModelContext
    ) throws -> Material {
        try create(
            title: nil,
            text: text,
            source: nil,
            topics: [],
            now: now,
            in: context
        )
    }

    @discardableResult
    static func fullCapture(
        title: String,
        text: String,
        source: String,
        topics: [Topic],
        now: Date = .now,
        in context: ModelContext
    ) throws -> Material {
        try create(
            title: title,
            text: text,
            source: source,
            topics: topics,
            now: now,
            in: context
        )
    }

    static func update(
        _ material: Material,
        title: String,
        text: String,
        source: String,
        topics: [Topic],
        now: Date = .now
    ) throws {
        guard let normalizedText = text.trimmedNonempty else {
            throw NoteValidationError.emptyText
        }

        let normalizedTitle = title.trimmedNonempty
        let normalizedSource = source.trimmedNonempty
        let normalizedTopics = unique(topics)
        let oldTopicIDs = Set(material.topics.map(\.id))
        let newTopicIDs = Set(normalizedTopics.map(\.id))

        let changed = material.title != normalizedTitle
            || material.text != normalizedText
            || material.source != normalizedSource
            || oldTopicIDs != newTopicIDs

        if changed {
            material.title = normalizedTitle
            material.text = normalizedText
            material.source = normalizedSource
            material.topics = normalizedTopics
            material.updatedAt = now
        }
        MaterialOrganizationService.synchronizeStatus(for: material)
    }

    static func inboxDescriptor() -> FetchDescriptor<Material> {
        FetchDescriptor(
            predicate: #Predicate { $0.statusRawValue == "inbox" },
            sortBy: [SortDescriptor(\Material.capturedAt, order: .reverse)]
        )
    }

    private static func create(
        title: String?,
        text: String,
        source: String?,
        topics: [Topic],
        now: Date,
        in context: ModelContext
    ) throws -> Material {
        guard let normalizedText = text.trimmedNonempty else {
            throw NoteValidationError.emptyText
        }

        let normalizedTopics = unique(topics)
        let material = Material(
            type: .note,
            status: MaterialOrganizationService.expectedStatus(forTopics: normalizedTopics),
            title: title?.trimmedNonempty,
            text: normalizedText,
            createdAt: now,
            updatedAt: now,
            capturedAt: now,
            source: source?.trimmedNonempty,
            topics: normalizedTopics
        )
        context.insert(material)
        return material
    }

    private static func unique(_ topics: [Topic]) -> [Topic] {
        var ids: Set<UUID> = []
        return topics.filter { ids.insert($0.id).inserted }
    }
}
