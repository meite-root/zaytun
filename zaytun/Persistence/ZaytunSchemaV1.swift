import Foundation
import SwiftData

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
}

enum ZaytunMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ZaytunSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
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
        let schema = Schema(versionedSchema: ZaytunSchemaV1.self)
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
