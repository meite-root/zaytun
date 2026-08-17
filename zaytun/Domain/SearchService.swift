import Foundation

struct MaterialSearchResult: Identifiable {
    let material: Material
    let matchingAttributions: [MaterialAttribution]

    var id: UUID { material.id }

    var provenanceSummary: String? {
        AttributionService.provenanceSummary(for: matchingAttributions)
    }
}

struct ZaytunSearchResults {
    let people: [Person]
    let topics: [Topic]
    let materials: [MaterialSearchResult]

    static let empty = ZaytunSearchResults(people: [], topics: [], materials: [])

    var isEmpty: Bool {
        people.isEmpty && topics.isEmpty && materials.isEmpty
    }
}

@MainActor
enum SearchService {
    static func search(
        query: String,
        materials: [Material],
        people: [Person],
        topics: [Topic]
    ) -> ZaytunSearchResults {
        guard let query = query.trimmedNonempty else { return .empty }

        let matchingPeople = people
            .filter { person in
                matches(person.displayName, query: query)
                    || matches(person.name, query: query)
            }
            .sorted(by: personOrder)

        let matchingTopics = topics
            .filter { matches($0.title, query: query) }
            .sorted(by: topicOrder)

        var materialsByID: [UUID: Material] = [:]
        var attributionsByMaterialID: [UUID: [MaterialAttribution]] = [:]

        for material in materials where directlyMatches(material, query: query) {
            materialsByID[material.id] = material
        }

        for person in matchingPeople {
            for attribution in person.attributions {
                let material = attribution.material
                materialsByID[material.id] = material
                attributionsByMaterialID[material.id, default: []].append(attribution)
            }
        }

        for topic in matchingTopics {
            for material in topic.materials {
                materialsByID[material.id] = material
            }
        }

        let materialResults = materialsByID.values
            .map { material in
                var attributionIDs: Set<UUID> = []
                let attributions = (attributionsByMaterialID[material.id] ?? [])
                    .filter { attributionIDs.insert($0.id).inserted }
                return MaterialSearchResult(
                    material: material,
                    matchingAttributions: AttributionService.ordered(attributions)
                )
            }
            .sorted(by: materialOrder)

        return ZaytunSearchResults(
            people: matchingPeople,
            topics: matchingTopics,
            materials: materialResults
        )
    }

    private static func directlyMatches(_ material: Material, query: String) -> Bool {
        matches(material.title, query: query)
            || matches(material.text, query: query)
            || matches(material.extractedText, query: query)
            || matches(material.source, query: query)
    }

    private static func matches(_ value: String?, query: String) -> Bool {
        value?.localizedCaseInsensitiveContains(query) == true
    }

    private static func personOrder(_ left: Person, _ right: Person) -> Bool {
        if left.isSelf != right.isSelf {
            return left.isSelf
        }
        let nameOrder = left.displayName.localizedStandardCompare(right.displayName)
        return nameOrder == .orderedSame
            ? left.id.uuidString < right.id.uuidString
            : nameOrder == .orderedAscending
    }

    private static func topicOrder(_ left: Topic, _ right: Topic) -> Bool {
        let titleOrder = left.title.localizedStandardCompare(right.title)
        return titleOrder == .orderedSame
            ? left.id.uuidString < right.id.uuidString
            : titleOrder == .orderedAscending
    }

    private static func materialOrder(
        _ left: MaterialSearchResult,
        _ right: MaterialSearchResult
    ) -> Bool {
        let leftDate = max(left.material.capturedAt, left.material.updatedAt)
        let rightDate = max(right.material.capturedAt, right.material.updatedAt)
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        if left.material.capturedAt != right.material.capturedAt {
            return left.material.capturedAt > right.material.capturedAt
        }
        return left.id.uuidString < right.id.uuidString
    }
}
