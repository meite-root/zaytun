import Foundation
import SwiftData
import Testing
@testable import zaytun

@MainActor
@Suite(.serialized)
struct StageDOrganizationRevisionTests {
    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try ZaytunPersistence.makeContainer(isStoredInMemoryOnly: true)
        return (container, ModelContext(container))
    }

    private func refetch<T: PersistentModel>(
        _ type: T.Type,
        from context: ModelContext
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    @Test("Topic lifecycle keeps persisted Material organization status synchronized")
    func topicLifecycleSynchronizesStatus() throws {
        let (container, context) = try makeStore()
        let capturedAt = Date(timeIntervalSince1970: 2_100_000_000)
        let firstAssignedAt = capturedAt.addingTimeInterval(10)
        let secondAssignedAt = capturedAt.addingTimeInterval(20)
        let nonfinalRemovedAt = capturedAt.addingTimeInterval(30)
        let finalRemovedAt = capturedAt.addingTimeInterval(40)
        let materialID = try NoteService.quickCapture(
            text: "A developing thought",
            now: capturedAt,
            in: context
        ).id
        let firstTopic = try TopicService.create(title: "Science", in: context)
        let secondTopic = try TopicService.create(title: "Ethics", in: context)
        try context.save()

        var savedMaterial = try #require(
            refetch(Material.self, from: container.mainContext).first {
                $0.id == materialID
            }
        )
        let savedTopics = try refetch(Topic.self, from: container.mainContext)
        let savedFirstTopic = try #require(savedTopics.first { $0.id == firstTopic.id })
        let savedSecondTopic = try #require(savedTopics.first { $0.id == secondTopic.id })
        #expect(savedMaterial.status == .inbox)
        #expect(savedMaterial.topics.isEmpty)
        #expect(MaterialOrganizationService.isStatusConsistent(for: savedMaterial))

        TopicService.assign(savedFirstTopic, to: savedMaterial, now: firstAssignedAt)
        try container.mainContext.save()
        savedMaterial = try #require(refetch(Material.self, from: container.mainContext).first)
        #expect(savedMaterial.status == .organized)
        #expect(savedMaterial.topics.map(\.id) == [firstTopic.id])
        #expect(savedMaterial.updatedAt == firstAssignedAt)

        TopicService.assign(savedSecondTopic, to: savedMaterial, now: secondAssignedAt)
        try container.mainContext.save()
        savedMaterial = try #require(refetch(Material.self, from: container.mainContext).first)
        #expect(savedMaterial.status == .organized)
        #expect(Set(savedMaterial.topics.map(\.id)) == Set([firstTopic.id, secondTopic.id]))
        #expect(savedMaterial.updatedAt == secondAssignedAt)

        TopicService.remove(savedFirstTopic, from: savedMaterial, now: nonfinalRemovedAt)
        try container.mainContext.save()
        savedMaterial = try #require(refetch(Material.self, from: container.mainContext).first)
        #expect(savedMaterial.status == .organized)
        #expect(savedMaterial.topics.map(\.id) == [secondTopic.id])
        #expect(savedMaterial.updatedAt == nonfinalRemovedAt)

        TopicService.remove(savedSecondTopic, from: savedMaterial, now: finalRemovedAt)
        try container.mainContext.save()
        savedMaterial = try #require(refetch(Material.self, from: container.mainContext).first)
        #expect(savedMaterial.status == .inbox)
        #expect(savedMaterial.topics.isEmpty)
        #expect(savedMaterial.updatedAt == finalRemovedAt)
        #expect(MaterialOrganizationService.isStatusConsistent(for: savedMaterial))
    }

    @Test("Quick and Full Capture derive initial status from selected Topics")
    func captureDerivesInitialStatus() throws {
        let (container, context) = try makeStore()
        let firstTopic = try TopicService.create(title: "Education", in: context)
        let secondTopic = try TopicService.create(title: "Development", in: context)
        _ = try NoteService.quickCapture(text: "Quick", in: context)
        _ = try NoteService.fullCapture(
            title: "No Topic",
            text: "Unorganized",
            source: "",
            topics: [],
            in: context
        )
        _ = try NoteService.fullCapture(
            title: "One Topic",
            text: "Organized once",
            source: "Book",
            topics: [firstTopic],
            in: context
        )
        _ = try NoteService.fullCapture(
            title: "Several Topics",
            text: "Organized several ways",
            source: "Conversation",
            topics: [firstTopic, secondTopic],
            in: context
        )
        try context.save()

        let materials = try refetch(Material.self, from: container.mainContext)
        let quick = try #require(materials.first { $0.text == "Quick" })
        #expect(quick.status == .inbox)
        #expect(quick.topics.isEmpty)
        #expect(quick.source == nil)
        #expect(quick.attributions.isEmpty)
        #expect(materials.first { $0.title == "No Topic" }?.status == .inbox)
        #expect(materials.first { $0.title == "One Topic" }?.status == .organized)
        #expect(materials.first { $0.title == "Several Topics" }?.status == .organized)
        #expect(materials.allSatisfy {
            MaterialOrganizationService.isStatusConsistent(for: $0)
        })
    }

    @Test("Material editing and inline Topic creation use the same organization invariant")
    func editAndInlineCreationSynchronizeStatus() throws {
        let (container, context) = try makeStore()
        let material = try NoteService.quickCapture(text: "Inbox note", in: context)
        let topic = try TopicService.createAndAssign(
            title: "New Topic",
            to: material,
            in: context
        )
        try context.save()

        var savedMaterial = try #require(
            refetch(Material.self, from: container.mainContext).first
        )
        #expect(savedMaterial.status == .organized)
        #expect(savedMaterial.topics.map(\.id) == [topic.id])
        #expect(try refetch(Topic.self, from: container.mainContext).map(\.id) == [topic.id])

        try NoteService.update(
            savedMaterial,
            title: "",
            text: "Inbox note",
            source: "",
            topics: []
        )
        try container.mainContext.save()

        savedMaterial = try #require(refetch(Material.self, from: container.mainContext).first)
        #expect(savedMaterial.status == .inbox)
        #expect(savedMaterial.topics.isEmpty)
    }

    @Test("Deleting Topics synchronizes every affected Material without deleting endpoints")
    func topicDeletionSynchronizesAffectedMaterials() throws {
        let (container, context) = try makeStore()
        let deletedTopic = try TopicService.create(title: "Deleted", in: context)
        let survivingTopic = try TopicService.create(title: "Surviving", in: context)
        let onlyDeleted = try NoteService.fullCapture(
            title: "One Topic",
            text: "Returns to Inbox",
            source: "Book",
            topics: [deletedTopic],
            in: context
        )
        let several = try NoteService.fullCapture(
            title: "Two Topics",
            text: "Stays organized",
            source: "Conversation",
            topics: [deletedTopic, survivingTopic],
            in: context
        )
        let reflection = try ReflectionService.create(
            body: "The Reflection survives.",
            kind: .thought,
            materials: [onlyDeleted, several],
            topics: [deletedTopic],
            in: context
        )
        try context.save()

        let savedDeletedTopic = try #require(
            refetch(Topic.self, from: container.mainContext).first {
                $0.id == deletedTopic.id
            }
        )
        TopicService.delete(savedDeletedTopic, from: container.mainContext)
        try container.mainContext.save()

        let materials = try refetch(Material.self, from: container.mainContext)
        let savedOnlyDeleted = try #require(materials.first { $0.id == onlyDeleted.id })
        let savedSeveral = try #require(materials.first { $0.id == several.id })
        #expect(savedOnlyDeleted.topics.isEmpty)
        #expect(savedOnlyDeleted.status == .inbox)
        #expect(savedSeveral.topics.map(\.id) == [survivingTopic.id])
        #expect(savedSeveral.status == .organized)
        #expect(try refetch(Topic.self, from: container.mainContext).map(\.id) == [survivingTopic.id])
        #expect(try refetch(Reflection.self, from: container.mainContext).map(\.id) == [reflection.id])
        #expect(try refetch(Reflection.self, from: container.mainContext).first?.topics.isEmpty == true)
    }

    @Test("Startup reconciliation corrects only inconsistent status and is idempotent")
    func reconciliationIsSafeAndIdempotent() throws {
        let (container, context) = try makeStore()
        let base = Date(timeIntervalSince1970: 2_100_001_000)
        let topic = try TopicService.create(title: "Legacy Topic", in: context)
        let shouldBeOrganized = Material(
            type: .note,
            status: .inbox,
            title: "Legacy organized note",
            text: "Has a Topic",
            updatedAt: base,
            source: "Book",
            topics: [topic]
        )
        let shouldBeInbox = Material(
            type: .note,
            status: .organized,
            title: "Legacy Inbox note",
            text: "Has no Topic",
            updatedAt: base.addingTimeInterval(1),
            source: "Conversation"
        )
        context.insert(shouldBeOrganized)
        context.insert(shouldBeInbox)
        try context.save()

        let changed = try MaterialOrganizationService.reconcilePersistedStatuses(
            in: container.mainContext
        )
        let materials = try refetch(Material.self, from: container.mainContext)
        let savedOrganized = try #require(materials.first { $0.id == shouldBeOrganized.id })
        let savedInbox = try #require(materials.first { $0.id == shouldBeInbox.id })
        #expect(changed == 2)
        #expect(savedOrganized.status == .organized)
        #expect(savedOrganized.topics.map(\.id) == [topic.id])
        #expect(savedOrganized.title == "Legacy organized note")
        #expect(savedOrganized.text == "Has a Topic")
        #expect(savedOrganized.source == "Book")
        #expect(savedOrganized.updatedAt == base)
        #expect(savedInbox.status == .inbox)
        #expect(savedInbox.topics.isEmpty)
        #expect(savedInbox.title == "Legacy Inbox note")
        #expect(savedInbox.text == "Has no Topic")
        #expect(savedInbox.source == "Conversation")
        #expect(savedInbox.updatedAt == base.addingTimeInterval(1))

        let secondPass = try MaterialOrganizationService.reconcilePersistedStatuses(
            in: container.mainContext
        )
        #expect(secondPass == 0)
    }

    @Test("Reflections Home retrieval is unique, complete, empty-safe, and deterministic")
    func reflectionsHomeRetrieval() throws {
        let (container, context) = try makeStore()
        #expect(ReflectionService.allReflectionsRecentFirst([]).isEmpty)

        let base = Date(timeIntervalSince1970: 2_100_002_000)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let newestID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
        let material = try NoteService.quickCapture(text: "Context", in: context)
        let topic = try TopicService.create(title: "Context", in: context)
        let first = Reflection(
            id: firstID,
            body: "Same-time first",
            kind: .thought,
            createdAt: base,
            updatedAt: base,
            materials: [material],
            topics: [topic]
        )
        let second = Reflection(
            id: secondID,
            body: "Same-time second",
            kind: .question,
            createdAt: base,
            updatedAt: base,
            materials: [material],
            topics: [topic]
        )
        let newest = Reflection(
            id: newestID,
            body: "Newest",
            kind: .synthesis,
            createdAt: base.addingTimeInterval(10),
            updatedAt: base.addingTimeInterval(10),
            materials: [material],
            topics: [topic]
        )
        context.insert(first)
        context.insert(second)
        context.insert(newest)
        try context.save()

        let saved = try refetch(Reflection.self, from: container.mainContext)
        let ordered = ReflectionService.allReflectionsRecentFirst(
            saved + [try #require(saved.first)]
        )
        #expect(ordered.map(\.id) == [newestID, firstID, secondID])
        #expect(ordered.count == 3)
        #expect(Set(ordered.flatMap { $0.materials.map(\.id) }) == Set([material.id]))
        #expect(Set(ordered.flatMap { $0.topics.map(\.id) }) == Set([topic.id]))
    }
}
