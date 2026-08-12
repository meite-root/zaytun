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
    static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        if !isStoredInMemoryOnly {
            try FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory,
                withIntermediateDirectories: true
            )
        }
        let schema = Schema(versionedSchema: ZaytunSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: ZaytunMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
