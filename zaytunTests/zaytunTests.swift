import Foundation
import SwiftData
import Testing
@testable import zaytun

@MainActor
@Suite(.serialized)
struct ZaytunPersistenceTests {
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

    @Test("V1 schema contains exactly the six product models")
    func v1SchemaModels() throws {
        let expected = Set([
            "Material",
            "Reflection",
            "Topic",
            "Discipline",
            "Person",
            "MaterialAttribution",
        ])
        let declared = Set(ZaytunSchemaV1.models.map { String(describing: $0) })
        let container = try ZaytunPersistence.makeContainer(isStoredInMemoryOnly: true)
        let stored = Set(container.schema.entities.map(\.name))

        #expect(declared == expected)
        #expect(stored == expected)
        #expect(!stored.contains("Item"))
    }

    @Test("All six model types save and refetch")
    func allModelsPersist() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .note, text: "An observation")
        let topic = Topic(title: "Education")
        let reflection = Reflection(body: "A question", materials: [material], topics: [topic])
        let discipline = Discipline(name: "Sociology", topics: [topic])
        let person = Person(name: "Hamed")
        let attribution = MaterialAttribution(role: .saidBy, material: material, person: person)

        context.insert(material)
        context.insert(topic)
        context.insert(reflection)
        context.insert(discipline)
        context.insert(person)
        context.insert(attribution)
        try context.save()

        #expect(try refetch(Material.self, from: container).count == 1)
        #expect(try refetch(Reflection.self, from: container).count == 1)
        #expect(try refetch(Topic.self, from: container).count == 1)
        #expect(try refetch(Discipline.self, from: container).count == 1)
        #expect(try refetch(Person.self, from: container).count == 1)
        #expect(try refetch(MaterialAttribution.self, from: container).count == 1)
    }

    @Test("Bootstrap creates one self Person when none exists")
    func bootstrapCreatesSelf() throws {
        let (container, context) = try makeStore()
        let created = try SelfPersonBootstrap.ensureSelfPerson(in: context)
        let people = try refetch(Person.self, from: container)

        #expect(created.isSelf)
        #expect(created.name == nil)
        #expect(people.count == 1)
        #expect(people.first?.id == created.id)
        #expect(people.first?.displayName == "Me")
    }

    @Test("Bootstrap reuses the existing self identity")
    func bootstrapReusesSelf() throws {
        let (_, context) = try makeStore()
        let existing = Person(name: "Hassane", isSelf: true)
        context.insert(existing)
        try context.save()

        let returned = try SelfPersonBootstrap.ensureSelfPerson(in: context)

        #expect(returned.id == existing.id)
        #expect(returned.name == "Hassane")
        #expect(returned.displayName == "Me")
        #expect(try context.fetch(FetchDescriptor<Person>()).count == 1)
    }

    @Test("Bootstrap surfaces multiple self People without changing them")
    func bootstrapRejectsMultipleSelfPeople() throws {
        let (_, context) = try makeStore()
        context.insert(Person(isSelf: true))
        context.insert(Person(name: "Other self", isSelf: true))
        try context.save()

        do {
            _ = try SelfPersonBootstrap.ensureSelfPerson(in: context)
            Issue.record("Expected a multiple-self integrity error")
        } catch let error as SelfPersonIntegrityError {
            #expect(error == .multipleSelfPeople(count: 2))
        }

        #expect(try context.fetch(FetchDescriptor<Person>()).filter(\.isSelf).count == 2)
    }

    @Test("Controlled ordinary Person creation can only create nonself identities")
    func normalCreationIsNeverSelf() throws {
        let (_, context) = try makeStore()
        _ = try SelfPersonBootstrap.ensureSelfPerson(in: context)
        let ordinary = try PersonService.createNonself(name: "Hussein", in: context)
        try context.save()

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(!ordinary.isSelf)
        #expect(people.filter(\.isSelf).count == 1)
    }

    @Test(
        "Nonself names are trimmed and validated",
        arguments: ["", "   ", "\n\t"]
    )
    func invalidNonselfNames(name: String) throws {
        let (_, context) = try makeStore()
        #expect(throws: PersonValidationError.emptyName) {
            try PersonService.createNonself(name: name, in: context)
        }
    }

    @Test("Valid trimmed and duplicate nonself names persist")
    func duplicateNamesAreAllowed() throws {
        let (container, context) = try makeStore()
        let first = try PersonService.createNonself(name: "  Mohamed  ", in: context)
        let second = try PersonService.createNonself(name: "Mohamed", in: context)
        try context.save()

        let people = try refetch(Person.self, from: container)
        #expect(first.id != second.id)
        #expect(people.count == 2)
        #expect(people.allSatisfy { $0.name == "Mohamed" && !$0.isSelf })
    }

    @Test("Naming self edits but does not replace its identity")
    func namedSelfKeepsIdentity() throws {
        let (container, context) = try makeStore()
        let person = try SelfPersonBootstrap.ensureSelfPerson(in: context)
        let originalID = person.id
        try PersonService.rename(person, to: "  Hassane  ")
        try context.save()

        let saved = try #require(refetch(Person.self, from: container).first)
        #expect(saved.id == originalID)
        #expect(saved.name == "Hassane")
        #expect(saved.displayName == "Me")
    }

    @Test("Known roles persist their exact stable raw values")
    func knownRolePersistence() throws {
        for role in AttributionRole.supported {
            let (container, context) = try makeStore()
            let material = Material(type: .note, text: "Thought")
            let person = Person(name: "Hamed")
            context.insert(material)
            context.insert(person)
            _ = try AttributionService.create(material: material, person: person, role: role, in: context)
            try context.save()

            let saved = try #require(refetch(MaterialAttribution.self, from: container).first)
            #expect(saved.roleRawValue == role.rawValue)
            #expect(saved.role == role)
            #expect(saved.role.isSupported)
        }
    }

    @Test("An unknown role survives persistence without conversion")
    func unknownRolePersistence() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .note)
        let person = Person(name: "Future Person")
        let unknown = AttributionRole(rawValue: "inspiredBy")
        let attribution = MaterialAttribution(role: unknown, material: material, person: person)
        context.insert(material)
        context.insert(person)
        context.insert(attribution)
        try context.save()

        let saved = try #require(refetch(MaterialAttribution.self, from: container).first)
        #expect(saved.roleRawValue == "inspiredBy")
        #expect(saved.role == unknown)
        #expect(!saved.role.isSupported)
        #expect(saved.role.displayName == "Unsupported role")
    }

    @Test("Attribution endpoints and both inverses survive refetch")
    func attributionEndpointsPersist() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .image, title: "Diagram")
        let person = Person(name: "Hussein")
        context.insert(material)
        context.insert(person)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .sharedBy,
            in: context
        )
        try context.save()

        let savedAttribution = try #require(refetch(MaterialAttribution.self, from: container).first)
        let savedMaterial = try #require(refetch(Material.self, from: container).first)
        let savedPerson = try #require(refetch(Person.self, from: container).first)
        #expect(savedAttribution.id == attribution.id)
        #expect(savedAttribution.material.id == material.id)
        #expect(savedAttribution.person.id == person.id)
        #expect(savedMaterial.attributions.map(\.id) == [attribution.id])
        #expect(savedPerson.attributions.map(\.id) == [attribution.id])
    }

    @Test("Exact duplicate attribution is rejected")
    func exactDuplicateIsRejected() throws {
        let (_, context) = try makeStore()
        let material = Material(type: .video)
        let person = Person(name: "Hussein")
        context.insert(material)
        context.insert(person)
        _ = try AttributionService.create(material: material, person: person, role: .sharedBy, in: context)

        #expect(throws: AttributionValidationError.duplicate) {
            try AttributionService.create(material: material, person: person, role: .sharedBy, in: context)
        }
        #expect(material.attributions.count == 1)
    }

    @Test("Same Person can hold two roles on one Material")
    func samePersonDifferentRolesAllowed() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .video)
        let person = Person(name: "Hussein")
        context.insert(material)
        context.insert(person)
        _ = try AttributionService.create(material: material, person: person, role: .createdBy, in: context)
        _ = try AttributionService.create(material: material, person: person, role: .sharedBy, in: context)
        try context.save()

        let roles = Set(try refetch(MaterialAttribution.self, from: container).map(\.roleRawValue))
        #expect(roles == Set(["createdBy", "sharedBy"]))
    }

    @Test("Several People can share one role on a Material")
    func differentPeopleSameRoleAllowed() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .audio)
        let hamed = Person(name: "Hamed")
        let hussein = Person(name: "Hussein")
        context.insert(material)
        context.insert(hamed)
        context.insert(hussein)
        _ = try AttributionService.create(material: material, person: hamed, role: .saidBy, in: context)
        _ = try AttributionService.create(material: material, person: hussein, role: .saidBy, in: context)
        try context.save()

        let saved = try refetch(Material.self, from: container)
        #expect(saved.first?.attributions.count == 2)
        #expect(Set(saved.first?.attributions.map { $0.person.name } ?? []) == Set(["Hamed", "Hussein"]))
    }

    @Test("Changing a role rejects a duplicate but permits a distinct role")
    func roleEditingChecksDuplicates() throws {
        let (_, context) = try makeStore()
        let material = Material(type: .image)
        let person = Person(name: "Hussein")
        context.insert(material)
        context.insert(person)
        let created = try AttributionService.create(material: material, person: person, role: .createdBy, in: context)
        let shared = try AttributionService.create(material: material, person: person, role: .sharedBy, in: context)

        #expect(throws: AttributionValidationError.duplicate) {
            try AttributionService.updateRole(of: shared, to: .createdBy)
        }
        #expect(shared.role == .sharedBy)
        try AttributionService.updateRole(of: created, to: .saidBy)
        #expect(created.role == .saidBy)
    }

    @Test("Deleting Material removes attribution rows but preserves People")
    func deleteMaterialSafety() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .image)
        let person = Person(name: "Hussein")
        context.insert(material)
        context.insert(person)
        _ = try AttributionService.create(material: material, person: person, role: .sharedBy, in: context)
        try context.save()

        context.delete(material)
        try context.save()

        #expect(try refetch(Material.self, from: container).isEmpty)
        #expect(try refetch(MaterialAttribution.self, from: container).isEmpty)
        let savedPerson = try #require(refetch(Person.self, from: container).first)
        #expect(savedPerson.id == person.id)
        #expect(savedPerson.attributions.isEmpty)
    }

    @Test("Deleting Person removes attribution rows but preserves Materials")
    func deletePersonSafety() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .note)
        let person = Person(name: "Hamed")
        context.insert(material)
        context.insert(person)
        _ = try AttributionService.create(material: material, person: person, role: .saidBy, in: context)
        try context.save()

        context.delete(person)
        try context.save()

        #expect(try refetch(Person.self, from: container).isEmpty)
        #expect(try refetch(MaterialAttribution.self, from: container).isEmpty)
        let savedMaterial = try #require(refetch(Material.self, from: container).first)
        #expect(savedMaterial.id == material.id)
        #expect(savedMaterial.attributions.isEmpty)
    }

    @Test("Deleting attribution preserves both substantive endpoints")
    func deleteAttributionSafety() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .audio)
        let person = Person(name: "Hamed")
        context.insert(material)
        context.insert(person)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .saidBy,
            in: context
        )
        try context.save()

        context.delete(attribution)
        try context.save()

        #expect(try refetch(MaterialAttribution.self, from: container).isEmpty)
        #expect(try refetch(Material.self, from: container).count == 1)
        #expect(try refetch(Person.self, from: container).count == 1)
        #expect(try refetch(Material.self, from: container).first?.attributions.isEmpty == true)
        #expect(try refetch(Person.self, from: container).first?.attributions.isEmpty == true)
    }

    @Test("One Person can be attributed to many Materials")
    func onePersonManyMaterials() throws {
        let (container, context) = try makeStore()
        let person = Person(name: "Hussein")
        let first = Material(type: .image)
        let second = Material(type: .video)
        context.insert(person)
        context.insert(first)
        context.insert(second)
        _ = try AttributionService.create(material: first, person: person, role: .sharedBy, in: context)
        _ = try AttributionService.create(material: second, person: person, role: .sharedBy, in: context)
        try context.save()

        let savedPerson = try #require(refetch(Person.self, from: container).first)
        #expect(savedPerson.attributions.count == 2)
        #expect(Set(savedPerson.attributions.map { $0.material.id }) == Set([first.id, second.id]))
    }

    @Test("Deleting Person and Material together leaves no association rows")
    func deleteBothEndpointsTogether() throws {
        let (container, context) = try makeStore()
        let deletedMaterial = Material(type: .video)
        let survivingMaterial = Material(type: .note)
        let deletedPerson = Person(name: "Hussein")
        let survivingPerson = Person(name: "Hamed")
        context.insert(deletedMaterial)
        context.insert(survivingMaterial)
        context.insert(deletedPerson)
        context.insert(survivingPerson)
        _ = try AttributionService.create(material: deletedMaterial, person: deletedPerson, role: .sharedBy, in: context)
        _ = try AttributionService.create(material: deletedMaterial, person: survivingPerson, role: .saidBy, in: context)
        _ = try AttributionService.create(material: survivingMaterial, person: deletedPerson, role: .sharedBy, in: context)
        try context.save()

        context.delete(deletedMaterial)
        context.delete(deletedPerson)
        try context.save()

        let materials = try refetch(Material.self, from: container)
        let people = try refetch(Person.self, from: container)
        #expect(materials.map(\.id) == [survivingMaterial.id])
        #expect(people.map(\.id) == [survivingPerson.id])
        #expect(try refetch(MaterialAttribution.self, from: container).isEmpty)
        #expect(materials.first?.attributions.isEmpty == true)
        #expect(people.first?.attributions.isEmpty == true)
    }

    @Test("Existing intellectual relationships persist with explicit inverses")
    func existingRelationshipGraphPersists() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .note)
        let topic = Topic(title: "Language and Identity")
        let reflection = Reflection(body: "A synthesis")
        let discipline = Discipline(name: "Linguistics")
        context.insert(material)
        context.insert(topic)
        context.insert(reflection)
        context.insert(discipline)
        TopicService.assign(topic, to: material)
        reflection.materials.append(material)
        reflection.topics.append(topic)
        topic.disciplines.append(discipline)
        try context.save()

        let savedMaterial = try #require(refetch(Material.self, from: container).first)
        let savedReflection = try #require(refetch(Reflection.self, from: container).first)
        let savedTopic = try #require(refetch(Topic.self, from: container).first)
        let savedDiscipline = try #require(refetch(Discipline.self, from: container).first)
        #expect(savedMaterial.topics.map(\.id) == [topic.id])
        #expect(savedMaterial.reflections.map(\.id) == [reflection.id])
        #expect(savedReflection.materials.map(\.id) == [material.id])
        #expect(savedReflection.topics.map(\.id) == [topic.id])
        #expect(savedTopic.materials.map(\.id) == [material.id])
        #expect(savedTopic.reflections.map(\.id) == [reflection.id])
        #expect(savedTopic.disciplines.map(\.id) == [discipline.id])
        #expect(savedDiscipline.topics.map(\.id) == [topic.id])
    }

    @Test("Deleting Topic nullifies links without deleting intellectual objects")
    func topicDeletionSafety() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .note)
        let topic = Topic(title: "Language and Identity")
        let reflection = Reflection(body: "A synthesis")
        let discipline = Discipline(name: "Linguistics")
        context.insert(material)
        context.insert(topic)
        context.insert(reflection)
        context.insert(discipline)
        TopicService.assign(topic, to: material)
        reflection.topics.append(topic)
        topic.disciplines.append(discipline)
        try context.save()

        TopicService.delete(topic, from: context)
        try context.save()

        #expect(try refetch(Topic.self, from: container).isEmpty)
        #expect(try refetch(Material.self, from: container).count == 1)
        #expect(try refetch(Reflection.self, from: container).count == 1)
        #expect(try refetch(Discipline.self, from: container).count == 1)
        #expect(try refetch(Material.self, from: container).first?.topics.isEmpty == true)
        #expect(try refetch(Material.self, from: container).first?.status == .inbox)
        #expect(try refetch(Reflection.self, from: container).first?.topics.isEmpty == true)
        #expect(try refetch(Discipline.self, from: container).first?.topics.isEmpty == true)
    }

    @Test("Deleting Material never deletes its Reflections or Topics")
    func materialIntellectualDeletionSafety() throws {
        let (container, context) = try makeStore()
        let material = Material(type: .note)
        let topic = Topic(title: "Education")
        let reflection = Reflection(body: "Still valuable")
        context.insert(material)
        context.insert(topic)
        context.insert(reflection)
        TopicService.assign(topic, to: material)
        reflection.materials.append(material)
        reflection.topics.append(topic)
        try context.save()

        context.delete(material)
        try context.save()

        #expect(try refetch(Material.self, from: container).isEmpty)
        let savedReflection = try #require(refetch(Reflection.self, from: container).first)
        let savedTopic = try #require(refetch(Topic.self, from: container).first)
        #expect(savedReflection.materials.isEmpty)
        #expect(savedReflection.topics.map(\.id) == [savedTopic.id])
        #expect(savedTopic.materials.isEmpty)
        #expect(savedTopic.reflections.map(\.id) == [savedReflection.id])
    }
}
