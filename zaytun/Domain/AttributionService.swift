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

    static func ordered(
        _ attributions: [MaterialAttribution]
    ) -> [MaterialAttribution] {
        attributions.sorted { left, right in
            let leftOrder = presentationOrder(for: left.role)
            let rightOrder = presentationOrder(for: right.role)
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            if left.roleRawValue != right.roleRawValue {
                return left.roleRawValue < right.roleRawValue
            }
            let personOrder = left.person.displayName.localizedStandardCompare(
                right.person.displayName
            )
            if personOrder != .orderedSame {
                return personOrder == .orderedAscending
            }
            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    static func orderedRoles(_ roles: [AttributionRole]) -> [AttributionRole] {
        var seen: Set<String> = []
        return roles
            .filter { seen.insert($0.rawValue).inserted }
            .sorted { left, right in
                let leftOrder = presentationOrder(for: left)
                let rightOrder = presentationOrder(for: right)
                return leftOrder == rightOrder
                    ? left.rawValue < right.rawValue
                    : leftOrder < rightOrder
            }
    }

    static func roleSummary(_ roles: [AttributionRole]) -> String {
        orderedRoles(roles)
            .map(\.displayName)
            .joined(separator: " · ")
    }

    static func provenanceSummary(
        for attributions: [MaterialAttribution]
    ) -> String? {
        let grouped = Dictionary(grouping: ordered(attributions), by: \.roleRawValue)
        let values: [String] = orderedRoles(
            grouped.values.compactMap { $0.first?.role }
        ).compactMap { role -> String? in
            guard let matches = grouped[role.rawValue] else { return nil }
            var personIDs: Set<UUID> = []
            let names = matches
                .filter { personIDs.insert($0.person.id).inserted }
                .map { $0.person.displayName }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            guard !names.isEmpty else { return nil }
            return "\(role.displayName) \(names.joined(separator: ", "))"
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
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

    private static func presentationOrder(for role: AttributionRole) -> Int {
        AttributionRole.supported.firstIndex(of: role) ?? Int.max
    }
}
