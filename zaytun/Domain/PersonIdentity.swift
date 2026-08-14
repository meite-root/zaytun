import Foundation
import SwiftData

enum SelfPersonIntegrityError: LocalizedError, Equatable {
    case multipleSelfPeople(count: Int)

    var errorDescription: String? {
        switch self {
        case .multipleSelfPeople(let count):
            String(localized: "Zaytun found \(count) people marked as Me. No records were changed.")
        }
    }
}

enum PersonValidationError: LocalizedError, Equatable {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            String(localized: "Enter a name that is not empty.")
        }
    }
}

@MainActor
enum SelfPersonBootstrap {
    static func ensureSelfPerson(in context: ModelContext) throws -> Person {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.isSelf == true }
        )
        let matches = try context.fetch(descriptor)

        switch matches.count {
        case 0:
            let person = Person(isSelf: true)
            context.insert(person)
            try context.save()
            return person
        case 1:
            return matches[0]
        default:
            throw SelfPersonIntegrityError.multipleSelfPeople(count: matches.count)
        }
    }
}

@MainActor
enum PersonService {
    @discardableResult
    static func createNonself(name: String, in context: ModelContext) throws -> Person {
        let trimmedName = try validatedNonselfName(name)
        let person = Person(name: trimmedName, isSelf: false)
        context.insert(person)
        return person
    }

    static func validatedNonselfName(_ name: String) throws -> String {
        guard let trimmedName = name.trimmedNonempty else {
            throw PersonValidationError.emptyName
        }
        return trimmedName
    }

    static func rename(_ person: Person, to name: String, now: Date = .now) throws {
        if person.isSelf {
            person.name = name.trimmedNonempty
        } else {
            guard let trimmedName = name.trimmedNonempty else {
                throw PersonValidationError.emptyName
            }
            person.name = trimmedName
        }
        person.updatedAt = now
    }
}
