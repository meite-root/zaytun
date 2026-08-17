import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import zaytun

@MainActor
@Suite(.serialized)
struct ZaytunStageFMediaTests {
    private enum SyntheticFailure: Error {
        case save
    }

    private func makeStore() throws -> (ModelContainer, ModelContext) {
        let container = try ZaytunPersistence.makeContainer(isStoredInMemoryOnly: true)
        return (container, ModelContext(container))
    }

    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ZaytunMediaTests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceFile(
        in directory: URL,
        named filename: String,
        bytes: [UInt8] = [1, 2, 3, 4]
    ) throws -> URL {
        let url = directory.appending(path: filename)
        try Data(bytes).write(to: url)
        return url
    }

    private func refetch<T: PersistentModel>(
        _ type: T.Type,
        from container: ModelContainer
    ) throws -> [T] {
        try container.mainContext.fetch(FetchDescriptor<T>())
    }

    @Test("UTType detection and UUID filenames are unified across image, audio, and video")
    func typeDetectionAndCollisionSafeStorage() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try sourceFile(in: directory, named: "same-name.jpg")
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!

        #expect(SharedMediaKind.detect(contentType: .jpeg) == .image)
        #expect(SharedMediaKind.detect(contentType: .mp3) == .audio)
        #expect(SharedMediaKind.detect(contentType: .mpeg4Movie) == .video)
        #expect(SharedMediaKind.detect(contentType: .plainText) == nil)

        let first = try storage.copyIntoStorage(
            from: source,
            materialID: firstID,
            contentType: .jpeg,
            originalFilename: "same-name.jpg"
        )
        let second = try storage.copyIntoStorage(
            from: source,
            materialID: secondID,
            contentType: .jpeg,
            originalFilename: "same-name.jpg"
        )

        #expect(first != second)
        #expect(first.hasPrefix(firstID.uuidString))
        #expect(second.hasPrefix(secondID.uuidString))
        #expect(storage.existingURL(for: first) != nil)
        #expect(storage.existingURL(for: second) != nil)
        #expect(try Data(contentsOf: #require(storage.existingURL(for: first))) == Data([1, 2, 3, 4]))
    }

    @Test("Every media kind imports as a normal due Material with organization defaults")
    func importsCreateNormalMaterials() throws {
        let (container, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let imageSource = try sourceFile(in: directory, named: "image.jpg")
        let audioSource = try sourceFile(in: directory, named: "audio.mp3")
        let videoSource = try sourceFile(in: directory, named: "video.mp4")
        let topic = try TopicService.create(title: "Learning", in: context)
        let now = Date(timeIntervalSince1970: 1_800_100_000)

        let image = try MediaImportService.importMedia(
            from: imageSource,
            contentType: .jpeg,
            originalFilename: "image.jpg",
            title: "A diagram",
            source: nil,
            now: now,
            storage: storage,
            in: context
        )
        let audio = try MediaImportService.importMedia(
            from: audioSource,
            contentType: .mp3,
            originalFilename: "audio.mp3",
            now: now.addingTimeInterval(1),
            storage: storage,
            in: context
        )
        let video = try MediaImportService.importMedia(
            from: videoSource,
            contentType: .mpeg4Movie,
            originalFilename: "video.mp4",
            source: "Lecture",
            topics: [topic],
            now: now.addingTimeInterval(2),
            storage: storage,
            in: context
        )

        let saved = try refetch(Material.self, from: container)
        #expect(saved.count == 3)
        #expect(image.type == .image)
        #expect(audio.type == .audio)
        #expect(video.type == .video)
        #expect(image.status == .inbox && image.topics.isEmpty)
        #expect(audio.status == .inbox && audio.topics.isEmpty)
        #expect(video.status == .organized && video.topics.map(\.id) == [topic.id])
        #expect(image.source == nil)
        #expect(audio.attributions.isEmpty && video.attributions.isEmpty)
        for material in [image, audio, video] {
            #expect(material.lastReviewedAt == nil)
            #expect(material.reviewCount == 0)
            #expect(material.nextReviewAt == material.createdAt)
            #expect(!material.isArchived)
            #expect(storage.existingURL(for: material.mediaFilename) != nil)
            #expect(ResurfacingService.isDue(material, now: now.addingTimeInterval(2)))
        }
    }

    @Test("Copy and save failures leave neither a Material nor an owned binary")
    func failedImportsAreTransactional() throws {
        let (container, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appending(path: "Owned")
        let storage = MediaStorageService(rootURL: storageURL)
        let missingSource = directory.appending(path: "missing.mov")

        #expect(throws: MediaStorageError.missingSource) {
            try MediaImportService.importMedia(
                from: missingSource,
                contentType: .quickTimeMovie,
                storage: storage,
                in: context
            )
        }
        #expect(try refetch(Material.self, from: container).isEmpty)

        let source = try sourceFile(in: directory, named: "image.jpg")
        #expect(throws: SyntheticFailure.save) {
            try MediaImportService.importMedia(
                from: source,
                contentType: .jpeg,
                storage: storage,
                in: context,
                save: { _ in throw SyntheticFailure.save }
            )
        }
        #expect(try refetch(Material.self, from: container).isEmpty)
        let remainingFiles = (try? FileManager.default.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: nil
        )) ?? []
        #expect(remainingFiles.isEmpty)
    }

    @Test("Canceling a staged in-app selection removes only its temporary copy")
    func canceledSelectionLeavesNoPersistentState() throws {
        let (container, _) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try sourceFile(in: directory, named: "selected.jpg")
        let stagedURL = try MediaSelectionStaging.copyToTemporary(source).get()

        #expect(FileManager.default.fileExists(atPath: stagedURL.path))
        MediaSelectionStaging.removeTemporaryFile(at: stagedURL)

        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try refetch(Material.self, from: container).isEmpty)
        #expect(try refetch(Topic.self, from: container).isEmpty)
        #expect(try refetch(MaterialAttribution.self, from: container).isEmpty)
    }

    @Test("Missing binaries do not remove their Material records")
    func missingBinaryIsSafe() throws {
        let (container, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let source = try sourceFile(in: directory, named: "audio.mp3")
        let material = try MediaImportService.importMedia(
            from: source,
            contentType: .mp3,
            storage: storage,
            in: context
        )
        let filename = try #require(material.mediaFilename)
        try storage.removeFile(named: filename)

        #expect(storage.existingURL(for: filename) == nil)
        #expect(try refetch(Material.self, from: container).map(\.id) == [material.id])
        #expect(material.type == .audio)
    }

    @Test("Media uses the existing Topic, provenance, Reflection, Search, and deletion graph")
    func mediaUsesExistingIntellectualGraph() throws {
        let (container, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let source = try sourceFile(in: directory, named: "image.jpg")
        let topic = try TopicService.create(title: "Education", in: context)
        let person = try PersonService.createNonself(name: "Hussein", in: context)
        let material = try MediaImportService.importMedia(
            from: source,
            contentType: .jpeg,
            title: "School diagram",
            source: "Conversation",
            topics: [topic],
            storage: storage,
            in: context
        )
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .sharedBy,
            in: context
        )
        let reflection = try ReflectionService.create(
            body: "A visual connection",
            kind: .thought,
            materials: [material],
            topics: [topic],
            in: context
        )
        try context.save()

        let directSearch = SearchService.search(
            query: "School",
            materials: [material],
            people: [person],
            topics: [topic]
        )
        let personSearch = SearchService.search(
            query: "Hussein",
            materials: [material],
            people: [person],
            topics: [topic]
        )
        #expect(directSearch.materials.map(\.id) == [material.id])
        #expect(personSearch.materials.map(\.id) == [material.id])
        #expect(material.status == .organized)
        #expect(material.attributions.map(\.id) == [attribution.id])
        #expect(material.reflections.map(\.id) == [reflection.id])
        let ownedFilename = material.mediaFilename
        #expect(storage.existingURL(for: ownedFilename) != nil)

        try MediaImportService.delete(material, storage: storage, from: context)

        #expect(storage.existingURL(for: ownedFilename) == nil)
        #expect(try refetch(Material.self, from: container).isEmpty)
        #expect(try refetch(Person.self, from: container).map(\.id) == [person.id])
        #expect(try refetch(Topic.self, from: container).map(\.id) == [topic.id])
        #expect(try refetch(Reflection.self, from: container).map(\.id) == [reflection.id])
    }

    @Test("Shared queue manifests round-trip, reject unsupported types, and isolate filename collisions")
    func sharedQueueTransportIsSafe() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = SharedImportQueue(rootURL: directory.appending(path: "ImportQueue"))
        let source = try sourceFile(in: directory, named: "IMG_1234.jpg")
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let createdAt = Date(timeIntervalSince1970: 1_800_200_000)

        let first = try queue.stage(
            sourceURL: source,
            contentType: .jpeg,
            originalFilename: "IMG_1234.jpg",
            importID: firstID,
            createdAt: createdAt
        )
        let second = try queue.stage(
            sourceURL: source,
            contentType: .jpeg,
            originalFilename: "IMG_1234.jpg",
            importID: secondID,
            createdAt: createdAt
        )
        let entries = try queue.entries()

        #expect(entries.map(\.manifest.importID) == [firstID, secondID])
        #expect(first.directoryURL != second.directoryURL)
        #expect(first.payloadURL.lastPathComponent == second.payloadURL.lastPathComponent)
        #expect(first.manifest.originalFilename == "IMG_1234.jpg")
        #expect(first.manifest.contentTypeIdentifier == UTType.jpeg.identifier)
        #expect(throws: SharedImportQueueError.unsupportedContentType(UTType.plainText.identifier)) {
            try queue.stage(sourceURL: source, contentType: .plainText)
        }
    }

    @Test("Shared queue ingestion is multi-item, idempotent, cleans successes, and retains failures")
    func sharedQueueIngestionLifecycle() throws {
        let (container, context) = try makeStore()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = SharedImportQueue(rootURL: directory.appending(path: "ImportQueue"))
        let storage = MediaStorageService(rootURL: directory.appending(path: "Owned"))
        let imageSource = try sourceFile(in: directory, named: "item.jpg")
        let audioSource = try sourceFile(in: directory, named: "item.mp3")
        let imageID = UUID(uuidString: "00000000-0000-0000-0000-000000000081")!
        let audioID = UUID(uuidString: "00000000-0000-0000-0000-000000000082")!
        _ = try queue.stage(sourceURL: imageSource, contentType: .jpeg, importID: imageID)
        _ = try queue.stage(sourceURL: audioSource, contentType: .mp3, importID: audioID)

        let first = try SharedMediaIngestionService.ingestPending(
            queue: queue,
            storage: storage,
            in: context
        )
        let second = try SharedMediaIngestionService.ingestPending(
            queue: queue,
            storage: storage,
            in: context
        )
        #expect(first.importedCount == 2)
        #expect(first.failures.isEmpty)
        #expect(second.importedCount == 0)
        #expect(try queue.entries().isEmpty)
        #expect(Set(try refetch(Material.self, from: container).map(\.id)) == Set([imageID, audioID]))

        let alreadyID = UUID(uuidString: "00000000-0000-0000-0000-000000000083")!
        let staged = try queue.stage(sourceURL: imageSource, contentType: .jpeg, importID: alreadyID)
        _ = try MediaImportService.importMedia(
            from: staged.payloadURL,
            contentType: .jpeg,
            materialID: alreadyID,
            storage: storage,
            in: context
        )
        let resumed = try SharedMediaIngestionService.ingestPending(
            queue: queue,
            storage: storage,
            in: context
        )
        #expect(resumed.alreadyImportedCount == 1)
        #expect(try queue.entries().isEmpty)
        #expect(try refetch(Material.self, from: container).filter { $0.id == alreadyID }.count == 1)

        let failed = try queue.stage(sourceURL: audioSource, contentType: .mp3)
        try FileManager.default.removeItem(at: failed.payloadURL)
        #expect(throws: SharedImportQueueError.missingPayload) {
            try SharedMediaIngestionService.ingestPending(
                queue: queue,
                storage: storage,
                in: context
            )
        }
        #expect(FileManager.default.fileExists(atPath: failed.directoryURL.path))
    }
}
