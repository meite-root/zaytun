import Foundation
import SwiftData

struct PendingReflectionTopic: Identifiable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

struct ReflectionDraft {
    var body: String
    var kindRawValue: String
    var selectedMaterialIDs: Set<UUID>
    var selectedTopicIDs: Set<UUID>
    var pendingTopics: [PendingReflectionTopic]

    init(
        body: String = "",
        kindRawValue: String = ReflectionKind.thought.rawValue,
        selectedMaterialIDs: Set<UUID> = [],
        selectedTopicIDs: Set<UUID> = [],
        pendingTopics: [PendingReflectionTopic] = []
    ) {
        self.body = body
        self.kindRawValue = kindRawValue
        self.selectedMaterialIDs = selectedMaterialIDs
        self.selectedTopicIDs = selectedTopicIDs
        self.pendingTopics = pendingTopics
    }

    init(reflection: Reflection) {
        self.init(
            body: reflection.body,
            kindRawValue: reflection.kindRawValue,
            selectedMaterialIDs: Set(reflection.materials.map(\.id)),
            selectedTopicIDs: Set(reflection.topics.map(\.id)),
            pendingTopics: []
        )
    }
}

enum ReflectionValidationError: LocalizedError, Equatable {
    case emptyBody
    case unsupportedKind

    var errorDescription: String? {
        switch self {
        case .emptyBody:
            String(localized: "Write something before saving this Reflection.")
        case .unsupportedKind:
            String(localized: "Choose a supported Reflection type.")
        }
    }
}

@MainActor
enum ReflectionService {
    @discardableResult
    static func create(
        body: String,
        kind: ReflectionKind,
        materials: [Material],
        topics: [Topic],
        now: Date = .now,
        in context: ModelContext
    ) throws -> Reflection {
        let reflection = Reflection(
            body: try validatedBody(body),
            kind: kind,
            createdAt: now,
            updatedAt: now,
            materials: uniqueMaterials(materials),
            topics: uniqueTopics(topics)
        )
        context.insert(reflection)
        return reflection
    }

    static func update(
        _ reflection: Reflection,
        body: String,
        kind: ReflectionKind,
        materials: [Material],
        topics: [Topic],
        now: Date = .now
    ) throws {
        try update(
            reflection,
            body: body,
            kindRawValue: kind.rawValue,
            materials: materials,
            topics: topics,
            now: now
        )
    }

    static func update(
        _ reflection: Reflection,
        body: String,
        kindRawValue: String,
        materials: [Material],
        topics: [Topic],
        now: Date = .now
    ) throws {
        let normalizedBody = try validatedBody(body)
        let normalizedMaterials = uniqueMaterials(materials)
        let normalizedTopics = uniqueTopics(topics)
        let changed = reflection.body != normalizedBody
            || reflection.kindRawValue != kindRawValue
            || Set(reflection.materials.map(\.id)) != Set(normalizedMaterials.map(\.id))
            || Set(reflection.topics.map(\.id)) != Set(normalizedTopics.map(\.id))

        guard changed else { return }
        reflection.body = normalizedBody
        reflection.kindRawValue = kindRawValue
        reflection.materials = normalizedMaterials
        reflection.topics = normalizedTopics
        reflection.updatedAt = now
    }

    static func delete(_ reflection: Reflection, from context: ModelContext) {
        context.delete(reflection)
    }

    static func validatedBody(_ body: String) throws -> String {
        guard let normalizedBody = body.trimmedNonempty else {
            throw ReflectionValidationError.emptyBody
        }
        return normalizedBody
    }

    static func displayName(for reflection: Reflection) -> String {
        reflection.kind?.displayName ?? String(localized: "Unsupported")
    }

    static func reflections(for material: Material) -> [Reflection] {
        orderedUniqueReflections(material.reflections)
    }

    static func reflections(for topic: Topic) -> [Reflection] {
        orderedUniqueReflections(topic.reflections)
    }

    static func allReflectionsRecentFirst(
        _ reflections: [Reflection]
    ) -> [Reflection] {
        orderedUniqueReflections(reflections)
    }

    static func materials(for reflection: Reflection) -> [Material] {
        var materialsByID: [UUID: Material] = [:]
        for material in reflection.materials {
            materialsByID[material.id] = material
        }
        return materialsByID.values.sorted(by: materialOrder)
    }

    static func topics(for reflection: Reflection) -> [Topic] {
        var topicsByID: [UUID: Topic] = [:]
        for topic in reflection.topics {
            topicsByID[topic.id] = topic
        }
        return topicsByID.values.sorted(by: topicOrder)
    }

    private static func orderedUniqueReflections(
        _ reflections: [Reflection]
    ) -> [Reflection] {
        var reflectionsByID: [UUID: Reflection] = [:]
        for reflection in reflections {
            reflectionsByID[reflection.id] = reflection
        }
        return reflectionsByID.values.sorted(by: reflectionOrder)
    }

    private static func uniqueMaterials(_ materials: [Material]) -> [Material] {
        var ids: Set<UUID> = []
        return materials.filter { ids.insert($0.id).inserted }
    }

    private static func uniqueTopics(_ topics: [Topic]) -> [Topic] {
        var ids: Set<UUID> = []
        return topics.filter { ids.insert($0.id).inserted }
    }

    private static func reflectionOrder(_ left: Reflection, _ right: Reflection) -> Bool {
        let leftDate = max(left.createdAt, left.updatedAt)
        let rightDate = max(right.createdAt, right.updatedAt)
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        if left.createdAt != right.createdAt {
            return left.createdAt > right.createdAt
        }
        return left.id.uuidString < right.id.uuidString
    }

    private static func materialOrder(_ left: Material, _ right: Material) -> Bool {
        let leftDate = max(left.capturedAt, left.updatedAt)
        let rightDate = max(right.capturedAt, right.updatedAt)
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        if left.capturedAt != right.capturedAt {
            return left.capturedAt > right.capturedAt
        }
        return left.id.uuidString < right.id.uuidString
    }

    private static func topicOrder(_ left: Topic, _ right: Topic) -> Bool {
        let titleOrder = left.title.localizedStandardCompare(right.title)
        return titleOrder == .orderedSame
            ? left.id.uuidString < right.id.uuidString
            : titleOrder == .orderedAscending
    }
}
