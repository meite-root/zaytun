import Foundation
import SwiftData
import Testing
@testable import zaytun

@MainActor
@Suite(.serialized)
struct ZaytunStageDTests {
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

    @Test("Standalone Reflection drafts are nonpersistent and save without relationships")
    func reflectionCreationAndValidation() throws {
        let (container, context) = try makeStore()
        let draft = ReflectionDraft(
            body: "Unsaved thought",
            pendingTopics: [PendingReflectionTopic(title: "Unsaved Topic")]
        )
        #expect(draft.body == "Unsaved thought")
        #expect(try refetch(Reflection.self, from: container).isEmpty)
        #expect(try refetch(Material.self, from: container).isEmpty)
        #expect(try refetch(Topic.self, from: container).isEmpty)

        #expect(throws: ReflectionValidationError.emptyBody) {
            try ReflectionService.create(
                body: "",
                kind: .thought,
                materials: [],
                topics: [],
                in: context
            )
        }
        #expect(throws: ReflectionValidationError.emptyBody) {
            try ReflectionService.create(
                body: " \n\t ",
                kind: .question,
                materials: [],
                topics: [],
                in: context
            )
        }
        #expect(try refetch(Reflection.self, from: container).isEmpty)

        let base = Date(timeIntervalSince1970: 2_000_000_000)
        let bodies = ["  A thought  ", "Why?", "A synthesis"]
        for (index, kind) in ReflectionKind.allCases.enumerated() {
            let now = base.addingTimeInterval(Double(index))
            _ = try ReflectionService.create(
                body: bodies[index],
                kind: kind,
                materials: [],
                topics: [],
                now: now,
                in: context
            )
        }
        try context.save()

        let reflections = try refetch(Reflection.self, from: container)
        #expect(reflections.count == 3)
        #expect(Set(reflections.map(\.kindRawValue)) == Set(["thought", "question", "synthesis"]))
        #expect(reflections.first { $0.kind == .thought }?.body == "A thought")
        #expect(reflections.allSatisfy { $0.materials.isEmpty && $0.topics.isEmpty })
        #expect(try refetch(Material.self, from: container).isEmpty)
        #expect(try refetch(Topic.self, from: container).isEmpty)
        for reflection in reflections {
            #expect(reflection.createdAt == reflection.updatedAt)
        }
    }

    @Test("Reflection and Material cardinalities and inverses persist without duplicates")
    func reflectionMaterialRelationships() throws {
        let (container, context) = try makeStore()
        let firstMaterial = Material(type: .note, title: "First")
        let secondMaterial = Material(type: .note, title: "Second")
        context.insert(firstMaterial)
        context.insert(secondMaterial)
        let spanning = try ReflectionService.create(
            body: "These may be compatible.",
            kind: .synthesis,
            materials: [firstMaterial, secondMaterial, firstMaterial],
            topics: [],
            in: context
        )
        let secondReflection = try ReflectionService.create(
            body: "What follows?",
            kind: .question,
            materials: [firstMaterial],
            topics: [],
            in: context
        )
        try context.save()

        let reflections = try refetch(Reflection.self, from: container)
        let materials = try refetch(Material.self, from: container)
        let savedSpanning = try #require(reflections.first { $0.id == spanning.id })
        let savedFirstMaterial = try #require(materials.first { $0.id == firstMaterial.id })
        let savedSecondMaterial = try #require(materials.first { $0.id == secondMaterial.id })
        #expect(Set(savedSpanning.materials.map(\.id)) == Set([firstMaterial.id, secondMaterial.id]))
        #expect(savedSpanning.materials.count == 2)
        #expect(Set(savedFirstMaterial.reflections.map(\.id)) == Set([spanning.id, secondReflection.id]))
        #expect(savedSecondMaterial.reflections.map(\.id) == [spanning.id])
    }

    @Test("Reflection and Topic cardinalities and inverses persist without duplicates")
    func reflectionTopicRelationships() throws {
        let (container, context) = try makeStore()
        let firstTopic = try TopicService.create(title: "Economics", in: context)
        let secondTopic = try TopicService.create(title: "Politics", in: context)
        let spanning = try ReflectionService.create(
            body: "The Topics overlap here.",
            kind: .thought,
            materials: [],
            topics: [firstTopic, secondTopic, firstTopic],
            in: context
        )
        let secondReflection = try ReflectionService.create(
            body: "Where is the boundary?",
            kind: .question,
            materials: [],
            topics: [firstTopic],
            in: context
        )
        try context.save()

        let reflections = try refetch(Reflection.self, from: container)
        let topics = try refetch(Topic.self, from: container)
        let savedSpanning = try #require(reflections.first { $0.id == spanning.id })
        let savedFirstTopic = try #require(topics.first { $0.id == firstTopic.id })
        let savedSecondTopic = try #require(topics.first { $0.id == secondTopic.id })
        #expect(Set(savedSpanning.topics.map(\.id)) == Set([firstTopic.id, secondTopic.id]))
        #expect(savedSpanning.topics.count == 2)
        #expect(Set(savedFirstTopic.reflections.map(\.id)) == Set([spanning.id, secondReflection.id]))
        #expect(savedSecondTopic.reflections.map(\.id) == [spanning.id])
    }

    @Test("One Reflection spans several Materials and Topics after refetch")
    func combinedReflectionRelationships() throws {
        let (container, context) = try makeStore()
        let firstMaterial = Material(type: .note, title: "Argument A")
        let secondMaterial = Material(type: .note, title: "Argument B")
        let firstTopic = try TopicService.create(title: "Development", in: context)
        let secondTopic = try TopicService.create(title: "Political Economy", in: context)
        context.insert(firstMaterial)
        context.insert(secondMaterial)
        let reflection = try ReflectionService.create(
            body: "These arguments may be compatible.",
            kind: .synthesis,
            materials: [firstMaterial, secondMaterial],
            topics: [firstTopic, secondTopic],
            in: context
        )
        try context.save()

        let saved = try #require(refetch(Reflection.self, from: container).first)
        #expect(saved.id == reflection.id)
        #expect(try refetch(Reflection.self, from: container).count == 1)
        #expect(Set(saved.materials.map(\.id)) == Set([firstMaterial.id, secondMaterial.id]))
        #expect(Set(saved.topics.map(\.id)) == Set([firstTopic.id, secondTopic.id]))
        #expect(try refetch(Material.self, from: container).allSatisfy { $0.reflections.map(\.id) == [reflection.id] })
        #expect(try refetch(Topic.self, from: container).allSatisfy { $0.reflections.map(\.id) == [reflection.id] })
    }

    @Test("Material-context Reflection creation changes no Topic, provenance, or status")
    func materialContextCreation() throws {
        let (container, context) = try makeStore()
        let topic = try TopicService.create(title: "Patience", in: context)
        let material = Material(
            type: .note,
            status: .organized,
            text: "A source Material",
            source: "Book",
            topics: [topic]
        )
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        context.insert(material)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .saidBy,
            in: context
        )
        let reflection = try ReflectionService.create(
            body: "This changes my interpretation.",
            kind: .thought,
            materials: [material],
            topics: [],
            in: context
        )
        try context.save()

        let savedReflection = try #require(refetch(Reflection.self, from: container).first)
        let savedMaterial = try #require(refetch(Material.self, from: container).first)
        #expect(savedReflection.id == reflection.id)
        #expect(savedReflection.materials.map(\.id) == [material.id])
        #expect(savedReflection.topics.isEmpty)
        #expect(savedMaterial.status == .organized)
        #expect(savedMaterial.source == "Book")
        #expect(savedMaterial.topics.map(\.id) == [topic.id])
        #expect(savedMaterial.attributions.map(\.id) == [attribution.id])
        #expect(try refetch(Person.self, from: container).map(\.id) == [person.id])
    }

    @Test("Topic-context Reflection creation does not inherit the Topic's Materials")
    func topicContextCreation() throws {
        let (container, context) = try makeStore()
        let topic = try TopicService.create(title: "Science", in: context)
        let material = Material(
            type: .note,
            status: .organized,
            title: "Scientific method",
            topics: [topic]
        )
        context.insert(material)
        let reflection = try ReflectionService.create(
            body: "What is my current assumption?",
            kind: .question,
            materials: [],
            topics: [topic],
            in: context
        )
        try context.save()

        let saved = try #require(refetch(Reflection.self, from: container).first)
        #expect(saved.id == reflection.id)
        #expect(saved.topics.map(\.id) == [topic.id])
        #expect(saved.materials.isEmpty)
        #expect(try refetch(Material.self, from: container).first?.reflections.isEmpty == true)
    }

    @Test("Reflection editing preserves identity, timestamps, raw values, and intentional relationships")
    func reflectionEditing() throws {
        let (container, context) = try makeStore()
        let createdAt = Date(timeIntervalSince1970: 2_000_001_000)
        let firstEditAt = createdAt.addingTimeInterval(100)
        let secondEditAt = createdAt.addingTimeInterval(200)
        let ignoredEditAt = createdAt.addingTimeInterval(300)
        let firstMaterial = Material(type: .note, title: "First")
        let secondMaterial = Material(type: .note, title: "Second")
        let firstTopic = try TopicService.create(title: "First Topic", in: context)
        let secondTopic = try TopicService.create(title: "Second Topic", in: context)
        context.insert(firstMaterial)
        context.insert(secondMaterial)
        let reflection = try ReflectionService.create(
            body: "Original",
            kind: .thought,
            materials: [firstMaterial],
            topics: [firstTopic],
            now: createdAt,
            in: context
        )
        try context.save()

        try ReflectionService.update(
            reflection,
            body: "  Revised  ",
            kind: .question,
            materials: reflection.materials,
            topics: reflection.topics,
            now: firstEditAt
        )
        #expect(reflection.createdAt == createdAt)
        #expect(reflection.updatedAt == firstEditAt)
        #expect(reflection.body == "Revised")
        #expect(reflection.kindRawValue == "question")
        #expect(reflection.materials.map(\.id) == [firstMaterial.id])
        #expect(reflection.topics.map(\.id) == [firstTopic.id])

        try ReflectionService.update(
            reflection,
            body: "Revised",
            kind: .question,
            materials: reflection.materials,
            topics: reflection.topics,
            now: ignoredEditAt
        )
        #expect(reflection.updatedAt == firstEditAt)

        try ReflectionService.update(
            reflection,
            body: "A broader understanding",
            kind: .synthesis,
            materials: [secondMaterial],
            topics: [secondTopic],
            now: secondEditAt
        )
        reflection.kindRawValue = "futureKind"
        try ReflectionService.update(
            reflection,
            body: "Future-safe edit",
            kindRawValue: reflection.kindRawValue,
            materials: reflection.materials,
            topics: reflection.topics,
            now: ignoredEditAt
        )
        try context.save()

        let saved = try #require(refetch(Reflection.self, from: container).first)
        #expect(saved.createdAt == createdAt)
        #expect(saved.updatedAt == ignoredEditAt)
        #expect(saved.body == "Future-safe edit")
        #expect(saved.kindRawValue == "futureKind")
        #expect(saved.kind == nil)
        #expect(ReflectionService.displayName(for: saved) == "Unsupported")
        #expect(saved.materials.map(\.id) == [secondMaterial.id])
        #expect(saved.topics.map(\.id) == [secondTopic.id])
        #expect(try refetch(Material.self, from: container).first { $0.id == firstMaterial.id }?.reflections.isEmpty == true)
        #expect(try refetch(Topic.self, from: container).first { $0.id == firstTopic.id }?.reflections.isEmpty == true)
    }

    @Test("Deleting a Reflection preserves every substantive endpoint")
    func reflectionDeletionSafety() throws {
        let (container, context) = try makeStore()
        let topic = try TopicService.create(title: "Education", in: context)
        let discipline = try DisciplineService.create(name: "Sociology", in: context)
        try TopicService.update(topic, title: topic.title, disciplines: [discipline])
        let material = Material(
            type: .note,
            status: .organized,
            title: "A Material",
            topics: [topic]
        )
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        context.insert(material)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .saidBy,
            in: context
        )
        _ = try ReflectionService.create(
            body: "A disposable Reflection",
            kind: .thought,
            materials: [material],
            topics: [topic],
            in: context
        )
        try context.save()

        let savedReflection = try #require(refetch(Reflection.self, from: container).first)
        ReflectionService.delete(savedReflection, from: container.mainContext)
        try container.mainContext.save()

        #expect(try refetch(Reflection.self, from: container).isEmpty)
        #expect(try refetch(Material.self, from: container).map(\.id) == [material.id])
        #expect(try refetch(Topic.self, from: container).map(\.id) == [topic.id])
        #expect(try refetch(Discipline.self, from: container).map(\.id) == [discipline.id])
        #expect(try refetch(Person.self, from: container).map(\.id) == [person.id])
        #expect(try refetch(MaterialAttribution.self, from: container).map(\.id) == [attribution.id])
        #expect(try refetch(Material.self, from: container).first?.reflections.isEmpty == true)
        #expect(try refetch(Topic.self, from: container).first?.reflections.isEmpty == true)
    }

    @Test("Deleting one Material and one Topic preserves a Reflection's remaining links")
    func endpointDeletionSafety() throws {
        let (container, context) = try makeStore()
        let deletedMaterial = Material(type: .note, title: "Deleted")
        let survivingMaterial = Material(type: .note, title: "Surviving")
        let deletedTopic = try TopicService.create(title: "Deleted Topic", in: context)
        let survivingTopic = try TopicService.create(title: "Surviving Topic", in: context)
        context.insert(deletedMaterial)
        context.insert(survivingMaterial)
        let reflection = try ReflectionService.create(
            body: "This remains connected.",
            kind: .synthesis,
            materials: [deletedMaterial, survivingMaterial],
            topics: [deletedTopic, survivingTopic],
            in: context
        )
        try context.save()

        let savedMaterials = try refetch(Material.self, from: container)
        let savedTopics = try refetch(Topic.self, from: container)
        container.mainContext.delete(try #require(savedMaterials.first { $0.id == deletedMaterial.id }))
        try container.mainContext.save()

        var savedReflection = try #require(refetch(Reflection.self, from: container).first)
        #expect(savedReflection.id == reflection.id)
        #expect(savedReflection.materials.map(\.id) == [survivingMaterial.id])
        #expect(savedReflection.topics.count == 2)

        TopicService.delete(
            try #require(savedTopics.first { $0.id == deletedTopic.id }),
            from: container.mainContext
        )
        try container.mainContext.save()

        savedReflection = try #require(refetch(Reflection.self, from: container).first)
        #expect(savedReflection.materials.map(\.id) == [survivingMaterial.id])
        #expect(savedReflection.topics.map(\.id) == [survivingTopic.id])
        #expect(try refetch(Material.self, from: container).map(\.id) == [survivingMaterial.id])
        #expect(try refetch(Topic.self, from: container).map(\.id) == [survivingTopic.id])
    }

    @Test("Dossier and Reflection navigation retrieval is unique and deterministic")
    func reflectionRetrievalOrdering() throws {
        let (container, context) = try makeStore()
        let base = Date(timeIntervalSince1970: 2_000_002_000)
        let olderMaterial = Material(
            type: .note,
            title: "Same title",
            updatedAt: base,
            capturedAt: base
        )
        let newerMaterial = Material(
            type: .note,
            title: "Same title",
            updatedAt: base.addingTimeInterval(10),
            capturedAt: base.addingTimeInterval(10)
        )
        let firstTopic = Topic(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            title: "Same Topic"
        )
        let secondTopic = Topic(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            title: "Same Topic"
        )
        context.insert(olderMaterial)
        context.insert(newerMaterial)
        context.insert(firstTopic)
        context.insert(secondTopic)
        let olderReflection = try ReflectionService.create(
            body: "Identical text",
            kind: .thought,
            materials: [olderMaterial, newerMaterial],
            topics: [firstTopic, secondTopic],
            now: base,
            in: context
        )
        let newerReflection = try ReflectionService.create(
            body: "Identical text",
            kind: .thought,
            materials: [olderMaterial],
            topics: [firstTopic],
            now: base.addingTimeInterval(20),
            in: context
        )
        try context.save()

        let savedMaterial = try #require(refetch(Material.self, from: container).first { $0.id == olderMaterial.id })
        let savedTopic = try #require(refetch(Topic.self, from: container).first { $0.id == firstTopic.id })
        let savedOlderReflection = try #require(refetch(Reflection.self, from: container).first { $0.id == olderReflection.id })
        #expect(ReflectionService.reflections(for: savedMaterial).map(\.id) == [newerReflection.id, olderReflection.id])
        #expect(ReflectionService.reflections(for: savedMaterial).count == 2)
        #expect(ReflectionService.reflections(for: savedTopic).map(\.id) == [newerReflection.id, olderReflection.id])
        #expect(ReflectionService.materials(for: savedOlderReflection).map(\.id) == [newerMaterial.id, olderMaterial.id])
        #expect(ReflectionService.topics(for: savedOlderReflection).map(\.id) == [firstTopic.id, secondTopic.id])
    }
}
