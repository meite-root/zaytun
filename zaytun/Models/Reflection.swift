import Foundation
import SwiftData

extension ZaytunSchemaV2 {
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

    var kind: ReflectionKind? {
        get { ReflectionKind(rawValue: kindRawValue) }
        set {
            guard let newValue else { return }
            kindRawValue = newValue.rawValue
        }
    }
}
}

typealias Reflection = ZaytunSchemaV2.Reflection
