import Foundation
import SwiftData

enum AttributionValidationError: LocalizedError, Equatable {
    case duplicate

    var errorDescription: String? {
        switch self {
        case .duplicate:
            String(localized: "That person already has this role for the material.")
        }
    }
}

@MainActor
enum AttributionService {
    @discardableResult
    static func create(
        material: Material,
        person: Person,
        role: AttributionRole,
        in context: ModelContext
    ) throws -> MaterialAttribution {
        guard !containsDuplicate(
            material: material,
            person: person,
            role: role,
            excluding: nil
        ) else {
            throw AttributionValidationError.duplicate
        }

        let attribution = MaterialAttribution(role: role, material: material, person: person)
        context.insert(attribution)
        return attribution
    }

    @discardableResult
    static func create(
        material: Material,
        newPersonNamed name: String,
        role: AttributionRole,
        in context: ModelContext
    ) throws -> MaterialAttribution {
        _ = try PersonService.validatedNonselfName(name)
        let person = try PersonService.createNonself(name: name, in: context)
        return try create(material: material, person: person, role: role, in: context)
    }

    static func updateRole(
        of attribution: MaterialAttribution,
        to role: AttributionRole
    ) throws {
        guard !containsDuplicate(
            material: attribution.material,
            person: attribution.person,
            role: role,
            excluding: attribution.id
        ) else {
            throw AttributionValidationError.duplicate
        }
        attribution.role = role
    }

    static func remove(
        _ attribution: MaterialAttribution,
        from context: ModelContext
    ) {
        context.delete(attribution)
    }

    private static func containsDuplicate(
        material: Material,
        person: Person,
        role: AttributionRole,
        excluding excludedID: UUID?
    ) -> Bool {
        material.attributions.contains {
            $0.id != excludedID
                && $0.person.id == person.id
                && $0.roleRawValue == role.rawValue
        }
    }
}
