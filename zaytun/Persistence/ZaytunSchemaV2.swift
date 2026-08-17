import SwiftData

enum ZaytunSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

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
