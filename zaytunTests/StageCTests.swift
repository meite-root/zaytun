import Foundation
import SwiftData
import Testing
@testable import zaytun

@MainActor
@Suite(.serialized)
struct ZaytunStageCTests {
    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try ZaytunPersistence.makeContainer(isStoredInMemoryOnly: true)
        return (container, ModelContext(container))
    }

    private func refetch<T: PersistentModel>(
        _ type: T.Type,
        from container: ModelContainer
    ) throws -> [T] {
        try container.mainContext.fetch(FetchDescriptor<T>())
    }

    @Test("Person Material retrieval is unique, role-aware, and deterministically ordered")
    func personMaterialRetrieval() throws {
        let (container, context) = try makeStore()
        let older = Date(timeIntervalSince1970: 1_900_000_000)
        let newer = older.addingTimeInterval(100)
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        let first = Material(
            type: .note,
            title: "First",
            updatedAt: older,
            capturedAt: older
        )
        let second = Material(
            type: .video,
            title: "Second",
            updatedAt: newer,
            capturedAt: newer
        )
        context.insert(first)
        context.insert(second)
        _ = try AttributionService.create(material: first, person: person, role: .sharedBy, in: context)
        _ = try AttributionService.create(material: first, person: person, role: .createdBy, in: context)
        _ = try AttributionService.create(material: first, person: person, role: .saidBy, in: context)
        let futureRole = MaterialAttribution(
            role: AttributionRole(rawValue: "inspiredBy"),
            material: first,
            person: person
        )
        context.insert(futureRole)
        _ = try AttributionService.create(material: second, person: person, role: .sharedBy, in: context)
        try context.save()

        let savedPerson = try #require(refetch(Person.self, from: container).first)
        let links = PersonService.materialLinks(for: savedPerson)

        #expect(links.map(\.id) == [second.id, first.id])
        #expect(links[0].roles == [.sharedBy])
        #expect(links[1].roles.map(\.rawValue) == ["createdBy", "saidBy", "sharedBy", "inspiredBy"])
        #expect(links[1].roleSummary == "Created by · Said by · Shared by · Unsupported role")
    }

    @Test("Each Person independently retrieves a shared Material with their own roles")
    func multiplePeopleRetrieval() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .video, title: "Lecture")
        let professor = try PersonService.createNonself(name: "Professor A", in: context)
        let hussein = try PersonService.createNonself(name: "Hussein", in: context)
        context.insert(material)
        _ = try AttributionService.create(material: material, person: professor, role: .createdBy, in: context)
        _ = try AttributionService.create(material: material, person: hussein, role: .sharedBy, in: context)
        try context.save()

        let people = try refetch(Person.self, from: container)
        let savedProfessor = try #require(people.first { $0.id == professor.id })
        let savedHussein = try #require(people.first { $0.id == hussein.id })

        #expect(PersonService.materialLinks(for: savedProfessor).map(\.id) == [material.id])
        #expect(PersonService.materialLinks(for: savedProfessor).first?.roles == [.createdBy])
        #expect(PersonService.materialLinks(for: savedHussein).map(\.id) == [material.id])
        #expect(PersonService.materialLinks(for: savedHussein).first?.roles == [.sharedBy])
    }

    @Test("Renaming a Person preserves identity and provenance while duplicate names remain valid")
    func personRenamePreservesIdentity() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .note, text: "A quotation")
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        let duplicate = try PersonService.createNonself(name: "Ahmed", in: context)
        context.insert(material)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .saidBy,
            in: context
        )
        try context.save()

        let originalID = person.id
        try PersonService.rename(person, to: "  Ahmed  ")
        #expect(throws: PersonValidationError.emptyName) {
            try PersonService.rename(person, to: "  \n ")
        }
        try context.save()

        let people = try refetch(Person.self, from: container)
        let saved = try #require(people.first { $0.id == originalID })
        #expect(saved.name == "Ahmed")
        #expect(duplicate.id != saved.id)
        #expect(people.filter { $0.name == "Ahmed" }.count == 2)
        #expect(saved.attributions.map(\.id) == [attribution.id])
        #expect(saved.attributions.first?.material.id == material.id)
    }

    @Test("Deleting a nonself Person removes only their provenance links")
    func personDeletionIsSafe() throws {
        let (container, context) = try makeStore()
        let topic = try TopicService.create(title: "Education", in: context)
        let material = try NoteService.fullCapture(
            title: "Expectations",
            text: "A durable note",
            source: "Conversation",
            topics: [topic],
            in: context
        )
        let deletedPerson = try PersonService.createNonself(name: "Hussein", in: context)
        let survivingPerson = try PersonService.createNonself(name: "Hamed", in: context)
        _ = try AttributionService.create(
            material: material,
            person: deletedPerson,
            role: .sharedBy,
            in: context
        )
        let survivingAttribution = try AttributionService.create(
            material: material,
            person: survivingPerson,
            role: .saidBy,
            in: context
        )
        try context.save()

        try PersonService.delete(deletedPerson, from: context)
        try context.save()

        let savedMaterial = try #require(refetch(Material.self, from: container).first)
        let people = try refetch(Person.self, from: container)
        #expect(people.map(\.id) == [survivingPerson.id])
        #expect(savedMaterial.title == "Expectations")
        #expect(savedMaterial.text == "A durable note")
        #expect(savedMaterial.source == "Conversation")
        #expect(savedMaterial.status == .organized)
        #expect(savedMaterial.topics.map(\.id) == [topic.id])
        #expect(savedMaterial.attributions.map(\.id) == [survivingAttribution.id])
        #expect(try refetch(Topic.self, from: container).count == 1)
        #expect(try refetch(MaterialAttribution.self, from: container).count == 1)
    }

    @Test("Me is searchable, role-capable, renameable, and protected from ordinary deletion")
    func selfPersonStageCBehavior() throws {
        let (container, context) = try makeStore()
        let me = try SelfPersonBootstrap.ensureSelfPerson(in: context)
        let material = Material(type: .note, text: "A spontaneous thought")
        context.insert(material)
        _ = try AttributionService.create(material: material, person: me, role: .createdBy, in: context)
        try PersonService.rename(me, to: "  Hassane  ")
        try context.save()

        #expect(me.displayName == "Me")
        #expect(me.name == "Hassane")
        #expect(PersonService.materialLinks(for: me).map(\.id) == [material.id])
        #expect(throws: PersonDeletionError.selfPersonIsProtected) {
            try PersonService.delete(me, from: context)
        }

        let results = SearchService.search(
            query: "mE",
            materials: try refetch(Material.self, from: container),
            people: try refetch(Person.self, from: container),
            topics: []
        )
        #expect(results.people.map(\.id) == [me.id])
        #expect(results.materials.map(\.id) == [material.id])
        #expect(try refetch(Person.self, from: container).map(\.id) == [me.id])
    }

    @Test("Person search is case-insensitive, keeps duplicate identities, and returns attributed Materials")
    func personAwareSearch() throws {
        let (container, context) = try makeStore()
        let firstPerson = try PersonService.createNonself(name: "Hamed", in: context)
        let secondPerson = try PersonService.createNonself(name: "HAMED", in: context)
        let firstMaterial = Material(type: .note, title: "First quotation")
        let secondMaterial = Material(type: .audio, title: "Second quotation")
        context.insert(firstMaterial)
        context.insert(secondMaterial)
        _ = try AttributionService.create(material: firstMaterial, person: firstPerson, role: .saidBy, in: context)
        _ = try AttributionService.create(material: secondMaterial, person: secondPerson, role: .sharedBy, in: context)
        try context.save()

        let results = SearchService.search(
            query: "haMEd",
            materials: try refetch(Material.self, from: container),
            people: try refetch(Person.self, from: container),
            topics: []
        )

        #expect(Set(results.people.map(\.id)) == Set([firstPerson.id, secondPerson.id]))
        #expect(Set(results.materials.map(\.id)) == Set([firstMaterial.id, secondMaterial.id]))
        #expect(results.materials.allSatisfy { $0.matchingAttributions.count == 1 })
        #expect(Set(results.materials.compactMap(\.provenanceSummary)) == Set(["Said by Hamed", "Shared by HAMED"]))
    }

    @Test("Search merges direct, Topic, and Person matches without merging distinct Materials")
    func searchDeduplication() throws {
        let (container, context) = try makeStore()
        let topic = try TopicService.create(title: "Memory", in: context)
        let person = try PersonService.createNonself(name: "Memory", in: context)
        let first = try NoteService.fullCapture(
            title: "Memory",
            text: "First object",
            source: "Book",
            topics: [topic],
            in: context
        )
        let second = try NoteService.fullCapture(
            title: "Memory",
            text: "Second object",
            source: "Conversation",
            topics: [],
            in: context
        )
        _ = try AttributionService.create(material: first, person: person, role: .saidBy, in: context)
        try context.save()

        let results = SearchService.search(
            query: "memory",
            materials: try refetch(Material.self, from: container),
            people: try refetch(Person.self, from: container),
            topics: try refetch(Topic.self, from: container)
        )

        #expect(results.people.map(\.id) == [person.id])
        #expect(results.topics.map(\.id) == [topic.id])
        #expect(Set(results.materials.map(\.id)) == Set([first.id, second.id]))
        #expect(results.materials.count == 2)
        #expect(results.materials.first { $0.id == first.id }?.matchingAttributions.count == 1)
        #expect(results.materials.first { $0.id == second.id }?.matchingAttributions.isEmpty == true)
    }

    @Test("Search covers Material fields and Topic associations with stable recency ordering")
    func searchCoverageAndOrdering() throws {
        let (container, context) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_900_001_000)
        let topic = try TopicService.create(title: "Education", in: context)
        let titleMatch = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            type: .note,
            title: "Common Atlas",
            text: "quiet",
            updatedAt: base,
            capturedAt: base
        )
        let textMatch = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            type: .note,
            text: "A common constellation",
            updatedAt: base.addingTimeInterval(20),
            capturedAt: base.addingTimeInterval(20),
            topics: [topic]
        )
        let sourceMatch = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            type: .image,
            title: "Diagram",
            updatedAt: base.addingTimeInterval(10),
            capturedAt: base.addingTimeInterval(10),
            source: "Common WhatsApp"
        )
        context.insert(titleMatch)
        context.insert(textMatch)
        context.insert(sourceMatch)
        try context.save()

        let materials = try refetch(Material.self, from: container)
        let topics = try refetch(Topic.self, from: container)
        let common = SearchService.search(query: "common", materials: materials, people: [], topics: topics)
        #expect(common.materials.map(\.id) == [textMatch.id, sourceMatch.id, titleMatch.id])

        let topicResults = SearchService.search(query: "education", materials: materials, people: [], topics: topics)
        #expect(topicResults.topics.map(\.id) == [topic.id])
        #expect(topicResults.materials.map(\.id) == [textMatch.id])

        let empty = SearchService.search(query: " \n ", materials: materials, people: [], topics: topics)
        #expect(empty.isEmpty)
    }

    @Test("Topic Material retrieval is unique, recent-first, and survives refetch")
    func topicMaterialRetrieval() throws {
        let (container, context) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_900_002_000)
        let singleTopic = try TopicService.create(title: "Single", in: context)
        let severalTopic = try TopicService.create(title: "Several", in: context)
        let singleMaterial = Material(
            type: .note,
            title: "Only Material",
            updatedAt: base,
            capturedAt: base
        )
        let older = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            type: .note,
            title: "Same title",
            updatedAt: base.addingTimeInterval(10),
            capturedAt: base.addingTimeInterval(10)
        )
        let newer = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            type: .note,
            title: "Same title",
            updatedAt: base.addingTimeInterval(20),
            capturedAt: base.addingTimeInterval(20)
        )
        context.insert(singleMaterial)
        context.insert(older)
        context.insert(newer)
        TopicService.assign(singleTopic, to: singleMaterial, now: base)
        TopicService.assign(severalTopic, to: older, now: base.addingTimeInterval(10))
        TopicService.assign(severalTopic, to: newer, now: base.addingTimeInterval(20))
        TopicService.assign(severalTopic, to: older, now: base.addingTimeInterval(30))
        try context.save()

        let topics = try refetch(Topic.self, from: container)
        let savedSingleTopic = try #require(topics.first { $0.id == singleTopic.id })
        let savedSeveralTopic = try #require(topics.first { $0.id == severalTopic.id })

        #expect(TopicService.materials(for: savedSingleTopic).map(\.id) == [singleMaterial.id])
        #expect(TopicService.materials(for: savedSeveralTopic).map(\.id) == [newer.id, older.id])
        #expect(TopicService.materials(for: savedSeveralTopic).count == 2)
    }

    @Test("Topic association removal and deletion preserve the intellectual graph")
    func topicMaterialRelationshipSafety() throws {
        let (container, context) = try makeStore()
        let firstTopic = try TopicService.create(title: "First Topic", in: context)
        let deletedTopic = try TopicService.create(title: "Deleted Topic", in: context)
        let discipline = try DisciplineService.create(name: "Science", in: context)
        try TopicService.update(deletedTopic, title: deletedTopic.title, disciplines: [discipline])
        let material = Material(
            type: .note,
            status: .organized,
            title: "Shared Material",
            text: "Content survives Topic deletion.",
            source: "Book"
        )
        let reflection = Reflection(
            body: "A surviving Reflection",
            materials: [material],
            topics: [deletedTopic]
        )
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        context.insert(material)
        context.insert(reflection)
        TopicService.assign(firstTopic, to: material)
        TopicService.assign(deletedTopic, to: material)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .saidBy,
            in: context
        )
        try context.save()

        let savedTopics = try refetch(Topic.self, from: container)
        let savedFirstTopic = try #require(savedTopics.first { $0.id == firstTopic.id })
        let savedDeletedTopic = try #require(savedTopics.first { $0.id == deletedTopic.id })
        let savedMaterial = try #require(refetch(Material.self, from: container).first)
        #expect(TopicService.materials(for: savedFirstTopic).map(\.id) == [material.id])
        #expect(TopicService.materials(for: savedDeletedTopic).map(\.id) == [material.id])

        TopicService.remove(savedFirstTopic, from: savedMaterial)
        try container.mainContext.save()
        #expect(TopicService.materials(for: savedFirstTopic).isEmpty)
        #expect(TopicService.materials(for: savedDeletedTopic).map(\.id) == [material.id])
        #expect(try refetch(Material.self, from: container).count == 1)

        TopicService.delete(savedDeletedTopic, from: container.mainContext)
        try container.mainContext.save()

        let survivingMaterial = try #require(refetch(Material.self, from: container).first)
        #expect(survivingMaterial.id == material.id)
        #expect(survivingMaterial.title == "Shared Material")
        #expect(survivingMaterial.text == "Content survives Topic deletion.")
        #expect(survivingMaterial.source == "Book")
        #expect(survivingMaterial.status == .inbox)
        #expect(survivingMaterial.topics.isEmpty)
        #expect(survivingMaterial.attributions.map(\.id) == [attribution.id])
        #expect(try refetch(Person.self, from: container).map(\.id) == [person.id])
        #expect(try refetch(MaterialAttribution.self, from: container).map(\.id) == [attribution.id])
        #expect(try refetch(Reflection.self, from: container).map(\.id) == [reflection.id])
        #expect(try refetch(Discipline.self, from: container).map(\.id) == [discipline.id])
        #expect(try refetch(Topic.self, from: container).map(\.id) == [firstTopic.id])
    }
}
