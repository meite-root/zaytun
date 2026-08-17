import Foundation
import SwiftData

extension ZaytunSchemaV2 {
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

    var displayName: String {
        isSelf ? String(localized: "Me") : (name?.trimmedNonempty ?? String(localized: "Unnamed Person"))
    }
}
}

typealias Person = ZaytunSchemaV2.Person
