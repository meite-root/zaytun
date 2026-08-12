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
