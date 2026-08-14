import Foundation
import SwiftData
import Testing
@testable import zaytun

@MainActor
@Suite(.serialized)
struct ZaytunStageBTests {
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

    @Test("Quick Capture persists an ordinary metadata-free Inbox Note")
    func quickCaptureDefaults() throws {
        let (container, context) = try makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let material = try NoteService.quickCapture(
            text: "  I wonder whether infrastructure shapes memory.  ",
            now: now,
            in: context
        )
        try context.save()

        let saved = try #require(refetch(Material.self, from: container).first)
        #expect(saved.id == material.id)
        #expect(saved.typeRawValue == MaterialType.note.rawValue)
        #expect(saved.statusRawValue == MaterialStatus.inbox.rawValue)
        #expect(saved.text == "I wonder whether infrastructure shapes memory.")
        #expect(saved.title == nil)
        #expect(saved.source == nil)
        #expect(saved.topics.isEmpty)
        #expect(saved.attributions.isEmpty)
        #expect(saved.createdAt == now)
        #expect(saved.updatedAt == now)
        #expect(saved.capturedAt == now)
        #expect(saved.lastReviewedAt == nil)
        #expect(saved.nextReviewAt == nil)
        #expect(saved.reviewCount == 0)
        #expect(!saved.isArchived)
    }

    @Test("Quick Capture rejects empty text without inserting a Material")
    func quickCaptureRejectsEmptyText() throws {
        let (container, context) = try makeStore()

        #expect(throws: NoteValidationError.emptyText) {
            try NoteService.quickCapture(text: "  \n  ", in: context)
        }
        #expect(try refetch(Material.self, from: container).isEmpty)
    }

    @Test("Cancelling an untouched capture draft creates no persistent objects")
    func captureCancellationLeavesNoData() throws {
        let (container, _) = try makeStore()
        var draft = NoteCaptureDraft()
        draft.text = "A draft that is never submitted"
        draft.title = "Unsaved"
        draft.source = "Conversation"

        #expect(try refetch(Material.self, from: container).isEmpty)
        #expect(try refetch(Topic.self, from: container).isEmpty)
        #expect(try refetch(Person.self, from: container).isEmpty)
    }

    @Test("Full Capture supports zero, one, and multiple Topics with inverses")
    func fullCaptureTopicCardinality() throws {
        let (container, context) = try makeStore()
        let education = try TopicService.create(title: "Education", in: context)
        let development = try TopicService.create(title: "Development", in: context)

        _ = try NoteService.fullCapture(
            title: "",
            text: "No topic",
            source: "",
            topics: [],
            in: context
        )
        _ = try NoteService.fullCapture(
            title: "  Expectations  ",
            text: "One topic",
            source: "  Conversation  ",
            topics: [education],
            in: context
        )
        _ = try NoteService.fullCapture(
            title: "Several threads",
            text: "Multiple topics",
            source: "Book",
            topics: [education, development],
            in: context
        )
        try context.save()

        let materials = try refetch(Material.self, from: container)
        let topics = try refetch(Topic.self, from: container)
        #expect(materials.count == 3)
        #expect(materials.first { $0.text == "No topic" }?.topics.isEmpty == true)
        #expect(materials.first { $0.text == "One topic" }?.title == "Expectations")
        #expect(materials.first { $0.text == "One topic" }?.source == "Conversation")
        #expect(materials.first { $0.text == "One topic" }?.topics.map(\.id) == [education.id])
        #expect(Set(materials.first { $0.text == "Multiple topics" }?.topics.map(\.id) ?? []) == Set([education.id, development.id]))
        #expect(topics.first { $0.id == education.id }?.materials.count == 2)
        #expect(topics.first { $0.id == development.id }?.materials.count == 1)
    }

    @Test("Inbox membership and organization are persisted Material status")
    func inboxTransitionPersists() throws {
        let (container, context) = try makeStore()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_100)
        let organizedAt = Date(timeIntervalSince1970: 1_800_000_200)
        let material = try NoteService.quickCapture(text: "No metadata", now: createdAt, in: context)
        try context.save()

        #expect(try context.fetch(NoteService.inboxDescriptor()).map(\.id) == [material.id])

        NoteService.setStatus(.organized, for: material, now: organizedAt)
        try context.save()

        #expect(try context.fetch(NoteService.inboxDescriptor()).isEmpty)
        let saved = try #require(refetch(Material.self, from: container).first)
        #expect(saved.status == .organized)
        #expect(saved.updatedAt == organizedAt)
        #expect(saved.title == nil && saved.source == nil && saved.topics.isEmpty)

        NoteService.setStatus(.inbox, for: saved, now: organizedAt.addingTimeInterval(10))
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(NoteService.inboxDescriptor()).count == 1)
    }

    @Test("Editing a Note updates Stage B fields without changing creation or provenance")
    func materialEditingPreservesIdentityAndProvenance() throws {
        let (container, context) = try makeStore()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_300)
        let editedAt = Date(timeIntervalSince1970: 1_800_000_400)
        let material = try NoteService.quickCapture(text: "Original", now: createdAt, in: context)
        let education = try TopicService.create(title: "Education", in: context)
        let economics = try TopicService.create(title: "Economics", in: context)
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .saidBy,
            in: context
        )
        try context.save()

        try NoteService.update(
            material,
            title: "  A better title  ",
            text: "  Revised body  ",
            source: "  Conversation  ",
            topics: [education, economics],
            now: editedAt
        )
        try context.save()

        var saved = try #require(refetch(Material.self, from: container).first)
        #expect(saved.title == "A better title")
        #expect(saved.text == "Revised body")
        #expect(saved.source == "Conversation")
        #expect(saved.createdAt == createdAt)
        #expect(saved.capturedAt == createdAt)
        #expect(saved.updatedAt == editedAt)
        #expect(Set(saved.topics.map(\.id)) == Set([education.id, economics.id]))
        #expect(saved.attributions.map(\.id) == [attribution.id])
        #expect(saved.attributions.first?.person.id == person.id)

        try NoteService.update(
            saved,
            title: "A better title",
            text: "Revised body",
            source: "",
            topics: [economics],
            now: editedAt.addingTimeInterval(10)
        )
        try container.mainContext.save()

        saved = try #require(refetch(Material.self, from: container).first)
        #expect(saved.source == nil)
        #expect(saved.topics.map(\.id) == [economics.id])
        #expect(saved.attributions.map(\.id) == [attribution.id])
        #expect(try refetch(Topic.self, from: container).count == 2)
        #expect(try refetch(Person.self, from: container).count == 1)
    }

    @Test("Topic creation and rename trim names while allowing duplicate identities")
    func topicValidationAndRename() throws {
        let (container, context) = try makeStore()

        #expect(throws: OrganizationValidationError.emptyTopicName) {
            try TopicService.create(title: "   ", in: context)
        }
        let first = try TopicService.create(title: "  Education  ", in: context)
        let second = try TopicService.create(title: "Education", in: context)
        try context.save()

        try TopicService.update(first, title: "  Learning  ", disciplines: [])
        try context.save()

        let topics = try refetch(Topic.self, from: container)
        #expect(topics.count == 2)
        #expect(first.id != second.id)
        #expect(topics.first { $0.id == first.id }?.title == "Learning")
        #expect(topics.first { $0.id == second.id }?.title == "Education")
    }

    @Test("Topic relationships support many-to-many assignment, removal, and safe deletion")
    func topicRelationshipLifecycle() throws {
        let (container, context) = try makeStore()
        let firstMaterial = try NoteService.quickCapture(text: "First", in: context)
        let secondMaterial = try NoteService.quickCapture(text: "Second", in: context)
        let education = try TopicService.create(title: "Education", in: context)
        let policy = try TopicService.create(title: "Policy", in: context)
        try NoteService.update(firstMaterial, title: "", text: "First", source: "", topics: [education, policy])
        try NoteService.update(secondMaterial, title: "", text: "Second", source: "", topics: [education])
        try context.save()

        #expect(education.materials.count == 2)
        #expect(firstMaterial.topics.count == 2)

        try NoteService.update(firstMaterial, title: "", text: "First", source: "", topics: [policy])
        try context.save()
        #expect(education.materials.map(\.id) == [secondMaterial.id])
        #expect(try refetch(Material.self, from: container).count == 2)

        context.delete(policy)
        try context.save()
        let materials = try refetch(Material.self, from: container)
        #expect(materials.count == 2)
        #expect(materials.first { $0.id == firstMaterial.id }?.topics.isEmpty == true)
        #expect(materials.first { $0.id == secondMaterial.id }?.topics.map(\.id) == [education.id])
    }

    @Test("Discipline validation, rename, and many-to-many Topic assignment persist")
    func disciplineRelationshipsPersist() throws {
        let (container, context) = try makeStore()
        #expect(throws: OrganizationValidationError.emptyDisciplineName) {
            try DisciplineService.create(name: "\n", in: context)
        }

        let education = try TopicService.create(title: "Education", in: context)
        let language = try TopicService.create(title: "Language", in: context)
        let sociology = try DisciplineService.create(name: "  Sociology  ", in: context)
        let humanities = try DisciplineService.create(name: "Humanities", in: context)
        try TopicService.update(education, title: education.title, disciplines: [sociology, humanities])
        try TopicService.update(language, title: language.title, disciplines: [humanities])
        try DisciplineService.rename(sociology, to: "  Social Science  ")
        try context.save()

        let topics = try refetch(Topic.self, from: container)
        let disciplines = try refetch(Discipline.self, from: container)
        #expect(disciplines.first { $0.id == sociology.id }?.name == "Social Science")
        #expect(Set(topics.first { $0.id == education.id }?.disciplines.map(\.id) ?? []) == Set([sociology.id, humanities.id]))
        #expect(disciplines.first { $0.id == humanities.id }?.topics.count == 2)

        try TopicService.update(education, title: education.title, disciplines: [sociology])
        try context.save()
        #expect(humanities.topics.map(\.id) == [language.id])
    }

    @Test("Deleting a Discipline preserves Topics, Materials, and provenance")
    func disciplineDeletionIsSafe() throws {
        let (container, context) = try makeStore()
        let topic = try TopicService.create(title: "Education", in: context)
        let discipline = try DisciplineService.create(name: "Sociology", in: context)
        let material = try NoteService.fullCapture(
            title: "",
            text: "A note",
            source: "Conversation",
            topics: [topic],
            in: context
        )
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        _ = try AttributionService.create(material: material, person: person, role: .saidBy, in: context)
        try TopicService.update(topic, title: topic.title, disciplines: [discipline])
        try context.save()

        context.delete(discipline)
        try context.save()

        #expect(try refetch(Discipline.self, from: container).isEmpty)
        #expect(try refetch(Topic.self, from: container).count == 1)
        #expect(try refetch(Material.self, from: container).count == 1)
        #expect(try refetch(Person.self, from: container).count == 1)
        #expect(try refetch(MaterialAttribution.self, from: container).count == 1)
        #expect(try refetch(Topic.self, from: container).first?.disciplines.isEmpty == true)
        #expect(try refetch(Material.self, from: container).first?.topics.map(\.id) == [topic.id])
    }

    @Test("Stage B graph survives destruction and recreation of a disk container")
    func graphPersistsAcrossContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ZaytunStageB-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Zaytun.store")

        let materialID: UUID
        let topicID: UUID
        let disciplineID: UUID
        let personID: UUID

        do {
            let container = try ZaytunPersistence.makeContainer(storeURL: storeURL)
            let context = ModelContext(container)
            let topic = try TopicService.create(title: "Education", in: context)
            let discipline = try DisciplineService.create(name: "Sociology", in: context)
            try TopicService.update(topic, title: topic.title, disciplines: [discipline])
            let material = try NoteService.fullCapture(
                title: "Expectations",
                text: "A durable note",
                source: "Conversation",
                topics: [topic],
                in: context
            )
            let person = try PersonService.createNonself(name: "Hamed", in: context)
            _ = try AttributionService.create(material: material, person: person, role: .saidBy, in: context)
            NoteService.setStatus(.organized, for: material)
            try context.save()

            materialID = material.id
            topicID = topic.id
            disciplineID = discipline.id
            personID = person.id
        }

        do {
            let container = try ZaytunPersistence.makeContainer(storeURL: storeURL)
            let context = ModelContext(container)
            let material = try #require(context.fetch(FetchDescriptor<Material>()).first)
            let topic = try #require(context.fetch(FetchDescriptor<Topic>()).first)
            let discipline = try #require(context.fetch(FetchDescriptor<Discipline>()).first)
            let person = try #require(context.fetch(FetchDescriptor<Person>()).first)

            #expect(material.id == materialID)
            #expect(material.status == .organized)
            #expect(material.source == "Conversation")
            #expect(material.topics.map(\.id) == [topicID])
            #expect(material.attributions.first?.person.id == personID)
            #expect(topic.disciplines.map(\.id) == [disciplineID])
            #expect(discipline.topics.map(\.id) == [topicID])
            #expect(person.attributions.first?.material.id == materialID)
        }
    }
}
