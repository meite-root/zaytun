import Foundation
import SwiftData

/// The immutable, shipped Stage A-F persistence shape.
///
/// Keep these model declarations frozen. New persisted properties belong in a
/// later versioned schema so SwiftData can identify and migrate V1 stores.
enum ZaytunSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Material.self,
            Reflection.self,
            Topic.self,
            Discipline.self,
            Person.self,
            MaterialAttribution.self,
        ]
    }

    @Model
    final class Material {
        @Attribute(.unique) var id: UUID
        var typeRawValue: String
        var statusRawValue: String
        var title: String?
        var text: String?
        var mediaFilename: String?
        var contentTypeIdentifier: String?
        var createdAt: Date
        var updatedAt: Date
        var capturedAt: Date
        var source: String?
        var lastReviewedAt: Date?
        var nextReviewAt: Date?
        var reviewCount: Int
        var isArchived: Bool

        @Relationship(deleteRule: .nullify, inverse: \Topic.materials)
        var topics: [Topic]

        @Relationship(deleteRule: .nullify, inverse: \Reflection.materials)
        var reflections: [Reflection]

        @Relationship(deleteRule: .cascade, inverse: \MaterialAttribution.material)
        var attributions: [MaterialAttribution]

        init(
            id: UUID = UUID(),
            type: MaterialType,
            status: MaterialStatus = .inbox,
            title: String? = nil,
            text: String? = nil,
            mediaFilename: String? = nil,
            contentTypeIdentifier: String? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            capturedAt: Date = .now,
            source: String? = nil,
            lastReviewedAt: Date? = nil,
            nextReviewAt: Date? = nil,
            reviewCount: Int = 0,
            isArchived: Bool = false,
            topics: [Topic] = [],
            reflections: [Reflection] = [],
            attributions: [MaterialAttribution] = []
        ) {
            self.id = id
            self.typeRawValue = type.rawValue
            self.statusRawValue = status.rawValue
            self.title = title
            self.text = text
            self.mediaFilename = mediaFilename
            self.contentTypeIdentifier = contentTypeIdentifier
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.capturedAt = capturedAt
            self.source = source
            self.lastReviewedAt = lastReviewedAt
            self.nextReviewAt = nextReviewAt
            self.reviewCount = reviewCount
            self.isArchived = isArchived
            self.topics = topics
            self.reflections = reflections
            self.attributions = attributions
        }
    }

    @Model
    final class Reflection {
        @Attribute(.unique) var id: UUID
        var body: String
        var kindRawValue: String
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .nullify)
        var materials: [Material]

        @Relationship(deleteRule: .nullify, inverse: \Topic.reflections)
        var topics: [Topic]

        init(
            id: UUID = UUID(),
            body: String,
            kind: ReflectionKind = .thought,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            materials: [Material] = [],
            topics: [Topic] = []
        ) {
            self.id = id
            self.body = body
            self.kindRawValue = kind.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.materials = materials
            self.topics = topics
        }
    }

    @Model
    final class Topic {
        @Attribute(.unique) var id: UUID
        var title: String
        var currentUnderstanding: String
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .nullify)
        var materials: [Material]

        @Relationship(deleteRule: .nullify)
        var reflections: [Reflection]

        @Relationship(deleteRule: .nullify, inverse: \Discipline.topics)
        var disciplines: [Discipline]

        init(
            id: UUID = UUID(),
            title: String,
            currentUnderstanding: String = "",
            createdAt: Date = .now,
            updatedAt: Date = .now,
            materials: [Material] = [],
            reflections: [Reflection] = [],
            disciplines: [Discipline] = []
        ) {
            self.id = id
            self.title = title
            self.currentUnderstanding = currentUnderstanding
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.materials = materials
            self.reflections = reflections
            self.disciplines = disciplines
        }
    }

    @Model
    final class Discipline {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .nullify)
        var topics: [Topic]

        init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            topics: [Topic] = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.topics = topics
        }
    }

    @Model
    final class Person {
        @Attribute(.unique) var id: UUID
        var name: String?
        var isSelf: Bool
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \MaterialAttribution.person)
        var attributions: [MaterialAttribution]

        init(
            id: UUID = UUID(),
            name: String? = nil,
            isSelf: Bool = false,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            attributions: [MaterialAttribution] = []
        ) {
            self.id = id
            self.name = name
            self.isSelf = isSelf
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.attributions = attributions
        }
    }

    @Model
    final class MaterialAttribution {
        @Attribute(.unique) var id: UUID
        var roleRawValue: String
        var createdAt: Date

        @Relationship(deleteRule: .nullify)
        var material: Material

        @Relationship(deleteRule: .nullify)
        var person: Person

        init(
            id: UUID = UUID(),
            roleRawValue: String,
            createdAt: Date = .now,
            material: Material,
            person: Person
        ) {
            self.id = id
            self.roleRawValue = roleRawValue
            self.createdAt = createdAt
            self.material = material
            self.person = person
        }
    }
}

enum ZaytunMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ZaytunSchemaV1.self, ZaytunSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: ZaytunSchemaV1.self,
        toVersion: ZaytunSchemaV2.self
    )
}

enum ZaytunPersistence {
    static func makeContainer(
        isStoredInMemoryOnly: Bool = false,
        storeURL: URL? = nil
    ) throws -> ModelContainer {
        if !isStoredInMemoryOnly, storeURL == nil {
            try FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
        }
        let schema = Schema(versionedSchema: ZaytunSchemaV2.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: ZaytunMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
