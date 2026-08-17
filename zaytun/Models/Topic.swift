import Foundation
import SwiftData

extension ZaytunSchemaV2 {
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
}

typealias Topic = ZaytunSchemaV2.Topic
