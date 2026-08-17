import Foundation
import SwiftData
import Testing
@testable import zaytun

@MainActor
@Suite(.serialized)
struct StageBUXRevisionTests {
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

    @Test("Product provenance operations reuse Stage A identity and attribution rules")
    func productProvenanceLifecycle() throws {
        let (container, context) = try makeStore()
        let material = try NoteService.quickCapture(text: "Original thought", in: context)
        let me = try SelfPersonBootstrap.ensureSelfPerson(in: context)
        let hamed = try PersonService.createNonself(name: "Hamed", in: context)
        let shared = try AttributionService.create(
            material: material,
            person: hamed,
            role: .sharedBy,
            in: context
        )
        let created = try AttributionService.create(
            material: material,
            person: hamed,
            role: .createdBy,
            in: context
        )
        _ = try AttributionService.create(
            material: material,
            person: me,
            role: .createdBy,
            in: context
        )
        let newPersonAttribution = try AttributionService.create(
            material: material,
            newPersonNamed: "  Hussein  ",
            role: .saidBy,
            in: context
        )
        try context.save()

        #expect(throws: AttributionValidationError.duplicate) {
            try AttributionService.create(
                material: material,
                person: hamed,
                role: .sharedBy,
                in: context
            )
        }

        try AttributionService.updateRole(of: shared, to: .saidBy)
        try NoteService.update(
            material,
            title: "Revised",
            text: "Revised thought",
            source: "Conversation",
            topics: material.topics
        )
        AttributionService.remove(created, from: context)
        try context.save()

        let savedMaterial = try #require(refetch(Material.self, from: container).first)
        let people = try refetch(Person.self, from: container)
        let attributions = try refetch(MaterialAttribution.self, from: container)

        #expect(savedMaterial.title == "Revised")
        #expect(savedMaterial.attributions.count == 3)
        #expect(people.count == 3)
        #expect(people.first { $0.id == hamed.id } != nil)
        #expect(people.first { $0.id == me.id }?.displayName == "Me")
        #expect(newPersonAttribution.person.name == "Hussein")
        #expect(attributions.first { $0.id == shared.id }?.role == .saidBy)
        #expect(attributions.first { $0.id == created.id } == nil)
    }

    @Test("Draft validation creates no Person, Topic, or association")
    func draftValidationDoesNotPersistObjects() throws {
        let (container, _) = try makeStore()

        #expect(try PersonService.validatedNonselfName("  Hussein  ") == "Hussein")
        #expect(try TopicService.validatedTitle("  Parenting  ") == "Parenting")
        #expect(throws: PersonValidationError.emptyName) {
            try PersonService.validatedNonselfName(" \n ")
        }
        #expect(throws: OrganizationValidationError.emptyTopicName) {
            try TopicService.validatedTitle(" \t ")
        }

        #expect(try refetch(Person.self, from: container).isEmpty)
        #expect(try refetch(Topic.self, from: container).isEmpty)
        #expect(try refetch(MaterialAttribution.self, from: container).isEmpty)
    }

    @Test("Topic association operations are idempotent and preserve both endpoints")
    func productTopicAssociationLifecycle() throws {
        let (container, context) = try makeStore()
        let capturedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let assignedAt = capturedAt.addingTimeInterval(10)
        let ignoredDuplicateAt = capturedAt.addingTimeInterval(20)
        let removedAt = capturedAt.addingTimeInterval(30)
        let material = try NoteService.quickCapture(
            text: "A thought",
            now: capturedAt,
            in: context
        )
        let existing = try TopicService.create(title: "Education", in: context)
        try context.save()

        TopicService.assign(existing, to: material, now: assignedAt)
        TopicService.assign(existing, to: material, now: ignoredDuplicateAt)
        let created = try TopicService.createAndAssign(
            title: "  Parenting  ",
            to: material,
            now: assignedAt,
            in: context
        )
        try context.save()

        #expect(material.topics.count == 2)
        #expect(material.status == .organized)
        #expect(material.topics.filter { $0.id == existing.id }.count == 1)
        #expect(material.updatedAt == assignedAt)
        #expect(created.title == "Parenting")
        #expect(created.materials.map(\.id) == [material.id])

        TopicService.remove(existing, from: material, now: removedAt)
        try context.save()

        let savedMaterials = try refetch(Material.self, from: container)
        let savedTopics = try refetch(Topic.self, from: container)
        #expect(savedMaterials.count == 1)
        #expect(savedTopics.count == 2)
        #expect(savedMaterials.first?.topics.map(\.id) == [created.id])
        #expect(savedMaterials.first?.status == .organized)
        #expect(savedTopics.first { $0.id == existing.id }?.materials.isEmpty == true)
        #expect(savedTopics.first { $0.id == created.id }?.materials.map(\.id) == [material.id])
        #expect(savedMaterials.first?.updatedAt == removedAt)
    }
}
