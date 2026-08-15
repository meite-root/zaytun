import Foundation
import SwiftData

enum OrganizationValidationError: LocalizedError, Equatable {
    case emptyTopicName
    case emptyDisciplineName

    var errorDescription: String? {
        switch self {
        case .emptyTopicName:
            String(localized: "Enter a Topic name that is not empty.")
        case .emptyDisciplineName:
            String(localized: "Enter a Discipline name that is not empty.")
        }
    }
}

@MainActor
enum MaterialOrganizationService {
    static func expectedStatus(for material: Material) -> MaterialStatus {
        expectedStatus(forTopics: material.topics)
    }

    static func expectedStatus(forTopics topics: [Topic]) -> MaterialStatus {
        topics.isEmpty ? .inbox : .organized
    }

    static func isStatusConsistent(for material: Material) -> Bool {
        material.statusRawValue == expectedStatus(for: material).rawValue
    }

    @discardableResult
    static func synchronizeStatus(for material: Material) -> Bool {
        let expectedRawValue = expectedStatus(for: material).rawValue
        guard material.statusRawValue != expectedRawValue else { return false }
        material.statusRawValue = expectedRawValue
        return true
    }

    @discardableResult
    static func reconcilePersistedStatuses(in context: ModelContext) throws -> Int {
        let materials = try context.fetch(FetchDescriptor<Material>())
        let changedCount = materials.reduce(into: 0) { count, material in
            if synchronizeStatus(for: material) {
                count += 1
            }
        }
        if changedCount > 0 {
            try context.save()
        }
        return changedCount
    }
}

@MainActor
enum TopicService {
    @discardableResult
    static func create(
        title: String,
        now: Date = .now,
        in context: ModelContext
    ) throws -> Topic {
        let normalizedTitle = try validatedTitle(title)
        let topic = Topic(title: normalizedTitle, createdAt: now, updatedAt: now)
        context.insert(topic)
        return topic
    }

    static func validatedTitle(_ title: String) throws -> String {
        guard let normalizedTitle = title.trimmedNonempty else {
            throw OrganizationValidationError.emptyTopicName
        }
        return normalizedTitle
    }

    @discardableResult
    static func createAndAssign(
        title: String,
        to material: Material,
        now: Date = .now,
        in context: ModelContext
    ) throws -> Topic {
        let topic = try create(title: title, now: now, in: context)
        assign(topic, to: material, now: now)
        return topic
    }

    static func update(
        _ topic: Topic,
        title: String,
        disciplines: [Discipline],
        now: Date = .now
    ) throws {
        guard let normalizedTitle = title.trimmedNonempty else {
            throw OrganizationValidationError.emptyTopicName
        }

        let normalizedDisciplines = unique(disciplines)
        let changed = topic.title != normalizedTitle
            || Set(topic.disciplines.map(\.id)) != Set(normalizedDisciplines.map(\.id))

        guard changed else { return }
        topic.title = normalizedTitle
        topic.disciplines = normalizedDisciplines
        topic.updatedAt = now
    }

    static func assign(
        _ topic: Topic,
        to material: Material,
        now: Date = .now
    ) {
        if !material.topics.contains(where: { $0.id == topic.id }) {
            material.topics.append(topic)
            material.updatedAt = now
        }
        MaterialOrganizationService.synchronizeStatus(for: material)
    }

    static func remove(
        _ topic: Topic,
        from material: Material,
        now: Date = .now
    ) {
        if material.topics.contains(where: { $0.id == topic.id }) {
            material.topics.removeAll { $0.id == topic.id }
            material.updatedAt = now
        }
        MaterialOrganizationService.synchronizeStatus(for: material)
    }

    static func delete(
        _ topic: Topic,
        now: Date = .now,
        from context: ModelContext
    ) {
        let affectedMaterials = materials(for: topic)
        for material in affectedMaterials {
            remove(topic, from: material, now: now)
        }
        context.delete(topic)
    }

    static func materials(for topic: Topic) -> [Material] {
        var materialsByID: [UUID: Material] = [:]
        for material in topic.materials {
            materialsByID[material.id] = material
        }

        return materialsByID.values.sorted { left, right in
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
    }

    private static func unique(_ disciplines: [Discipline]) -> [Discipline] {
        var ids: Set<UUID> = []
        return disciplines.filter { ids.insert($0.id).inserted }
    }
}

@MainActor
enum DisciplineService {
    @discardableResult
    static func create(
        name: String,
        now: Date = .now,
        in context: ModelContext
    ) throws -> Discipline {
        guard let normalizedName = name.trimmedNonempty else {
            throw OrganizationValidationError.emptyDisciplineName
        }
        let discipline = Discipline(name: normalizedName, createdAt: now, updatedAt: now)
        context.insert(discipline)
        return discipline
    }

    static func rename(
        _ discipline: Discipline,
        to name: String,
        now: Date = .now
    ) throws {
        guard let normalizedName = name.trimmedNonempty else {
            throw OrganizationValidationError.emptyDisciplineName
        }
        guard discipline.name != normalizedName else { return }
        discipline.name = normalizedName
        discipline.updatedAt = now
    }
}
