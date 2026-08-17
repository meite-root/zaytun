import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import zaytun

@MainActor
@Suite(.serialized)
struct ZaytunStageGMediaUnderstandingTests {
    private enum SyntheticFailure: Error, Sendable {
        case processing
    }

    private nonisolated struct StubProcessor: MediaUnderstandingProcessing {
        var imageText: String? = nil
        var audioText: String? = nil
        var videoText: String? = nil
        var failingOperation: MediaUnderstandingOperation? = nil

        nonisolated func recognizeText(in imageURL: URL) async throws -> String? {
            if failingOperation == .imageRecognition { throw SyntheticFailure.processing }
            return imageText
        }

        nonisolated func transcribeAudio(
            at audioURL: URL,
            locale: Locale
        ) async throws -> String? {
            if failingOperation == .audioTranscription { throw SyntheticFailure.processing }
            return audioText
        }

        nonisolated func transcribeVideo(
            at videoURL: URL,
            locale: Locale
        ) async throws -> String? {
            if failingOperation == .videoTranscription { throw SyntheticFailure.processing }
            return videoText
        }
    }

    private struct LegacyIDs {
        let material: UUID
        let topic: UUID
        let reflection: UUID
        let discipline: UUID
        let person: UUID
        let attribution: UUID
    }

    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try ZaytunPersistence.makeContainer(isStoredInMemoryOnly: true)
        return (container, ModelContext(container))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "ZaytunStageGTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceFile(in directory: URL, named filename: String) throws -> URL {
        let url = directory.appending(path: filename)
        try Data([1, 2, 3, 4]).write(to: url)
        return url
    }

    private func importMaterial(
        type: MaterialType,
        storage: MediaStorageService,
        directory: URL,
        topics: [Topic] = [],
        in context: ModelContext
    ) throws -> Material {
        let (name, contentType): (String, UTType) = switch type {
        case .image: ("fixture.jpg", .jpeg)
        case .audio: ("fixture.mp3", .mp3)
        case .video: ("fixture.mp4", .mpeg4Movie)
        case .note: ("fixture.txt", .plainText)
        }
        return try MediaImportService.importMedia(
            from: sourceFile(in: directory, named: "\(UUID().uuidString)-\(name)"),
            contentType: contentType,
            topics: topics,
            storage: storage,
            in: context
        )
    }

    @Test("V1 migrates non-destructively to V2 with extractedText nil")
    func v1ToV2MigrationPreservesTheCompleteGraph() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Zaytun.store")

        let ids = try autoreleasepool { () throws -> LegacyIDs in
            let schema = Schema(versionedSchema: ZaytunSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let timestamp = Date(timeIntervalSince1970: 1_800_300_000)

            let material = ZaytunSchemaV1.Material(
                type: .note,
                status: .organized,
                title: "Legacy title",
                text: "User-authored legacy note",
                mediaFilename: "legacy.m4a",
                contentTypeIdentifier: UTType.mpeg4Audio.identifier,
                createdAt: timestamp,
                updatedAt: timestamp.addingTimeInterval(1),
                capturedAt: timestamp.addingTimeInterval(2),
                source: "Conversation",
                lastReviewedAt: timestamp.addingTimeInterval(3),
                nextReviewAt: timestamp.addingTimeInterval(4),
                reviewCount: 7,
                isArchived: true
            )
            let topic = ZaytunSchemaV1.Topic(
                title: "Legacy Topic",
                currentUnderstanding: "Understanding",
                createdAt: timestamp,
                updatedAt: timestamp,
                materials: [material]
            )
            let reflection = ZaytunSchemaV1.Reflection(
                body: "Legacy reflection",
                kind: .synthesis,
                createdAt: timestamp,
                updatedAt: timestamp,
                materials: [material],
                topics: [topic]
            )
            let discipline = ZaytunSchemaV1.Discipline(
                name: "Legacy Discipline",
                createdAt: timestamp,
                updatedAt: timestamp,
                topics: [topic]
            )
            let person = ZaytunSchemaV1.Person(
                name: "Legacy Person",
                createdAt: timestamp,
                updatedAt: timestamp
            )
            let attribution = ZaytunSchemaV1.MaterialAttribution(
                roleRawValue: AttributionRole.sharedBy.rawValue,
                createdAt: timestamp,
                material: material,
                person: person
            )

            for model in [material, topic, reflection, discipline, person, attribution] as [any PersistentModel] {
                context.insert(model)
            }
            try context.save()
            return LegacyIDs(
                material: material.id,
                topic: topic.id,
                reflection: reflection.id,
                discipline: discipline.id,
                person: person.id,
                attribution: attribution.id
            )
        }

        let migrated = try ZaytunPersistence.makeContainer(storeURL: storeURL)
        let context = migrated.mainContext
        let material = try #require(context.fetch(FetchDescriptor<Material>()).first)
        let topic = try #require(context.fetch(FetchDescriptor<Topic>()).first)
        let reflection = try #require(context.fetch(FetchDescriptor<Reflection>()).first)
        let discipline = try #require(context.fetch(FetchDescriptor<Discipline>()).first)
        let person = try #require(context.fetch(FetchDescriptor<Person>()).first)
        let attribution = try #require(context.fetch(FetchDescriptor<MaterialAttribution>()).first)

        #expect(material.id == ids.material)
        #expect(material.extractedText == nil)
        #expect(material.text == "User-authored legacy note")
        #expect(material.title == "Legacy title")
        #expect(material.source == "Conversation")
        #expect(material.mediaFilename == "legacy.m4a")
        #expect(material.contentTypeIdentifier == UTType.mpeg4Audio.identifier)
        #expect(material.status == .organized)
        #expect(material.reviewCount == 7 && material.isArchived)
        #expect(material.topics.map(\.id) == [ids.topic])
        #expect(material.reflections.map(\.id) == [ids.reflection])
        #expect(material.attributions.map(\.id) == [ids.attribution])
        #expect(topic.id == ids.topic && topic.disciplines.map(\.id) == [ids.discipline])
        #expect(reflection.id == ids.reflection && reflection.materials.map(\.id) == [ids.material])
        #expect(discipline.id == ids.discipline && discipline.topics.map(\.id) == [ids.topic])
        #expect(person.id == ids.person && person.attributions.map(\.id) == [ids.attribution])
        #expect(attribution.id == ids.attribution)
    }

    @Test("New Materials default extractedText to nil without changing Note text")
    func extractedTextDefaultsToNil() {
        let note = Material(type: .note, text: "Authored text")
        let image = Material(type: .image)

        #expect(note.text == "Authored text")
        #expect(note.extractedText == nil)
        #expect(image.text == nil)
        #expect(image.extractedText == nil)
    }

    @Test("Image recognition persists, is searchable, and reruns replace the prior result")
    func imageRecognitionPersistsSearchesAndReplaces() async throws {
        let (container, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let image = try importMaterial(
            type: .image,
            storage: storage,
            directory: directory,
            in: context
        )

        _ = try await MediaUnderstandingService.process(
            image,
            storage: storage,
            processor: StubProcessor(imageText: "Olive trees preserve memory"),
            in: context
        )
        #expect(image.extractedText == "Olive trees preserve memory")
        #expect(SearchService.search(
            query: "preserve",
            materials: [image],
            people: [],
            topics: []
        ).materials.map(\.id) == [image.id])

        _ = try await MediaUnderstandingService.process(
            image,
            storage: storage,
            processor: StubProcessor(imageText: "A replacement recognition"),
            in: context
        )
        #expect(image.extractedText == "A replacement recognition")
        #expect(try container.mainContext.fetch(FetchDescriptor<Material>()).first?.extractedText == "A replacement recognition")

        _ = try await MediaUnderstandingService.process(
            image,
            storage: storage,
            processor: StubProcessor(imageText: "  \n  "),
            in: context
        )
        #expect(image.extractedText == nil)
    }

    @Test("Recognition failure leaves image content and intellectual relationships unchanged")
    func imageFailurePreservesMaterialAndGraph() async throws {
        let (_, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let topic = try TopicService.create(title: "Ecology", in: context)
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        let image = try importMaterial(
            type: .image,
            storage: storage,
            directory: directory,
            topics: [topic],
            in: context
        )
        image.extractedText = "Existing recognition"
        let attribution = try AttributionService.create(
            material: image,
            person: person,
            role: .sharedBy,
            in: context
        )
        let reflection = try ReflectionService.create(
            body: "Keep this link",
            kind: .thought,
            materials: [image],
            topics: [topic],
            in: context
        )
        try context.save()

        do {
            _ = try await MediaUnderstandingService.process(
                image,
                storage: storage,
                processor: StubProcessor(failingOperation: .imageRecognition),
                in: context
            )
            Issue.record("Expected image recognition to fail")
        } catch {
            #expect(error as? MediaUnderstandingError == .textRecognitionFailed)
        }

        #expect(image.extractedText == "Existing recognition")
        #expect(image.status == .organized)
        #expect(image.topics.map(\.id) == [topic.id])
        #expect(image.attributions.map(\.id) == [attribution.id])
        #expect(image.reflections.map(\.id) == [reflection.id])
    }

    @Test("Audio and video transcripts persist and replace through their distinct routes")
    func audioAndVideoTranscriptsPersistAndReplace() async throws {
        let (container, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let audio = try importMaterial(type: .audio, storage: storage, directory: directory, in: context)
        let video = try importMaterial(type: .video, storage: storage, directory: directory, in: context)

        _ = try await MediaUnderstandingService.process(
            audio,
            storage: storage,
            processor: StubProcessor(audioText: "Audio transcript"),
            in: context
        )
        _ = try await MediaUnderstandingService.process(
            video,
            storage: storage,
            processor: StubProcessor(videoText: "Video transcript"),
            in: context
        )
        _ = try await MediaUnderstandingService.process(
            audio,
            storage: storage,
            processor: StubProcessor(audioText: "Updated audio transcript"),
            in: context
        )

        let refetched = try container.mainContext.fetch(FetchDescriptor<Material>())
        #expect(refetched.first { $0.id == audio.id }?.extractedText == "Updated audio transcript")
        #expect(refetched.first { $0.id == video.id }?.extractedText == "Video transcript")
    }

    @Test("Transcription failure preserves extracted text, organization, and provenance")
    func transcriptionFailurePreservesGraph() async throws {
        let (_, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let topic = try TopicService.create(title: "Cities", in: context)
        let person = try PersonService.createNonself(name: "Hussein", in: context)
        let audio = try importMaterial(
            type: .audio,
            storage: storage,
            directory: directory,
            topics: [topic],
            in: context
        )
        audio.extractedText = "Existing transcript"
        let attribution = try AttributionService.create(
            material: audio,
            person: person,
            role: .saidBy,
            in: context
        )
        try context.save()

        do {
            _ = try await MediaUnderstandingService.process(
                audio,
                storage: storage,
                processor: StubProcessor(failingOperation: .audioTranscription),
                in: context
            )
            Issue.record("Expected transcription to fail")
        } catch {
            #expect(error as? MediaUnderstandingError == .transcriptionUnavailable)
        }

        #expect(audio.extractedText == "Existing transcript")
        #expect(audio.status == .organized)
        #expect(audio.topics.map(\.id) == [topic.id])
        #expect(audio.attributions.map(\.id) == [attribution.id])
    }

    @Test("Note and unknown Material types fail safely while media routes are deterministic")
    func operationRoutingIsStrict() throws {
        #expect(try MediaUnderstandingService.operation(for: Material(type: .image)) == .imageRecognition)
        #expect(try MediaUnderstandingService.operation(for: Material(type: .audio)) == .audioTranscription)
        #expect(try MediaUnderstandingService.operation(for: Material(type: .video)) == .videoTranscription)
        #expect(throws: MediaUnderstandingError.unsupportedMaterial) {
            try MediaUnderstandingService.operation(for: Material(type: .note))
        }

        let unknown = Material(type: .image)
        unknown.typeRawValue = "future-media"
        #expect(throws: MediaUnderstandingError.unsupportedMaterial) {
            try MediaUnderstandingService.operation(for: unknown)
        }
    }

    @Test("Derived-text search deduplicates a Material matching every existing path")
    func searchDeduplicatesDerivedTextMatches() throws {
        let (_, context) = try makeStore()
        let topic = try TopicService.create(title: "Infrastructure", in: context)
        let person = try PersonService.createNonself(name: "Infrastructure", in: context)
        let material = Material(
            type: .audio,
            title: "Infrastructure",
            extractedText: "Urban infrastructure financing",
            source: "Infrastructure",
            topics: [topic]
        )
        context.insert(material)
        _ = try AttributionService.create(
            material: material,
            person: person,
            role: .sharedBy,
            in: context
        )
        try context.save()

        let results = SearchService.search(
            query: "Infrastructure",
            materials: [material],
            people: [person],
            topics: [topic]
        )
        #expect(results.materials.count == 1)
        #expect(results.materials.first?.id == material.id)
    }

    @Test("Missing binary preserves and searches transcript plus relationships")
    func missingBinaryWithTranscriptRemainsUseful() throws {
        let (_, context) = try makeStore()
        let topic = try TopicService.create(title: "Memory", in: context)
        let material = Material(
            type: .video,
            status: .organized,
            extractedText: "A distinctive surviving phrase",
            mediaFilename: "missing-video.mp4",
            contentTypeIdentifier: UTType.mpeg4Movie.identifier,
            topics: [topic]
        )
        context.insert(material)
        try context.save()

        #expect(SearchService.search(
            query: "surviving",
            materials: [material],
            people: [],
            topics: [topic]
        ).materials.map(\.id) == [material.id])
        #expect(material.extractedText == "A distinctive surviving phrase")
        #expect(material.topics.map(\.id) == [topic.id])
        #expect(material.status == .organized)
    }

    @Test("Persistence failure restores the previous derived text")
    func failedSaveRestoresPreviousText() async throws {
        let (_, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let image = try importMaterial(type: .image, storage: storage, directory: directory, in: context)
        image.extractedText = "Previous text"
        let previousUpdatedAt = image.updatedAt

        do {
            _ = try await MediaUnderstandingService.process(
                image,
                storage: storage,
                processor: StubProcessor(imageText: "Unsaved replacement"),
                in: context,
                save: { _ in throw SyntheticFailure.processing }
            )
            Issue.record("Expected persistence to fail")
        } catch {
            #expect(error as? MediaUnderstandingError == .persistenceFailed)
        }

        #expect(image.extractedText == "Previous text")
        #expect(image.updatedAt == previousUpdatedAt)
    }
}
