import Foundation
import SwiftData

extension ZaytunSchemaV2 {
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
}

typealias Discipline = ZaytunSchemaV2.Discipline
