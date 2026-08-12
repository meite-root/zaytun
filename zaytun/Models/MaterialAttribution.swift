import Foundation
import SwiftData

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

    convenience init(
        id: UUID = UUID(),
        role: AttributionRole,
        createdAt: Date = .now,
        material: Material,
        person: Person
    ) {
        self.init(
            id: id,
            roleRawValue: role.rawValue,
            createdAt: createdAt,
            material: material,
            person: person
        )
    }

    var role: AttributionRole {
        get { AttributionRole(rawValue: roleRawValue) }
        set { roleRawValue = newValue.rawValue }
    }
}
