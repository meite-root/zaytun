import Foundation
import SwiftData
import Testing
@testable import zaytun

@MainActor
@Suite(.serialized)
struct ZaytunStageETests {
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

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testNow(calendar: Calendar) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026,
                month: 8,
                day: 15,
                hour: 12,
                minute: 34,
                second: 56
            )
        )!
    }

    @Test("Quick and Full Capture create immediately due Materials with fresh review state")
    func creationDefaultsAreImmediatelyDue() throws {
        let (container, context) = try makeStore()
        let firstNow = Date(timeIntervalSince1970: 1_800_000_000)
        let secondNow = firstNow.addingTimeInterval(120)

        let quick = try NoteService.quickCapture(
            text: "Quick thought",
            now: firstNow,
            in: context
        )
        let full = try NoteService.fullCapture(
            title: "Full thought",
            text: "Full body",
            source: "Conversation",
            topics: [],
            now: secondNow,
            in: context
        )
        try context.save()

        let savedByID = Dictionary(uniqueKeysWithValues: try refetch(Material.self, from: container).map { ($0.id, $0) })
        for (material, creationDate) in [(quick, firstNow), (full, secondNow)] {
            let saved = try #require(savedByID[material.id])
            #expect(saved.lastReviewedAt == nil)
            #expect(saved.nextReviewAt == creationDate)
            #expect(saved.reviewCount == 0)
            #expect(!saved.isArchived)
            #expect(ResurfacingService.isDue(saved, now: creationDate))
        }
    }

    @Test("Good follows the complete calendar-day review ladder and preserves time of day")
    func goodUsesSuccessfulReviewLadder() throws {
        let calendar = testCalendar()
        let startingNow = testNow(calendar: calendar)
        let expectedDays = [1, 3, 7, 14, 30, 60, 90, 90]
        let material = Material(
            type: .note,
            text: "A durable idea",
            nextReviewAt: startingNow
        )

        for (index, intervalDays) in expectedDays.enumerated() {
            let reviewTime = try #require(calendar.date(
                byAdding: .hour,
                value: index,
                to: startingNow
            ))
            try ResurfacingService.markGood(
                material,
                at: reviewTime,
                calendar: calendar
            )
            let expectedDate = try #require(calendar.date(
                byAdding: .day,
                value: intervalDays,
                to: reviewTime
            ))

            #expect(material.reviewCount == index + 1)
            #expect(material.lastReviewedAt == reviewTime)
            #expect(material.nextReviewAt == expectedDate)
            #expect(calendar.component(.minute, from: expectedDate) == 34)
            #expect(calendar.component(.second, from: expectedDate) == 56)
            #expect(ResurfacingService.intervalAfterSuccessfulReview(index + 1) == intervalDays)
        }
    }

    @Test("Again records the attempt without advancing stage or changing the intellectual graph")
    func againAndGoodPreserveRelationshipsAndOrganization() throws {
        let (container, context) = try makeStore()
        let calendar = testCalendar()
        let now = testNow(calendar: calendar)
        let createdAt = now.addingTimeInterval(-20_000)
        let topic = try TopicService.create(title: "Education", in: context)
        let material = try NoteService.fullCapture(
            title: "A quotation",
            text: "Content",
            source: "Conversation",
            topics: [topic],
            now: createdAt,
            in: context
        )
        material.reviewCount = 2
        material.lastReviewedAt = now.addingTimeInterval(-10_000)
        material.nextReviewAt = now.addingTimeInterval(-60)
        let originalUpdatedAt = material.updatedAt
        let person = try PersonService.createNonself(name: "Hamed", in: context)
        let attribution = try AttributionService.create(
            material: material,
            person: person,
            role: .saidBy,
            in: context
        )
        let reflection = try ReflectionService.create(
            body: "A related thought",
            kind: .thought,
            materials: [material],
            topics: [topic],
            in: context
        )
        try context.save()

        ResurfacingService.markAgain(material, at: now)
        try context.save()

        var saved = try #require(refetch(Material.self, from: container).first)
        #expect(saved.lastReviewedAt == now)
        #expect(saved.nextReviewAt == now)
        #expect(saved.reviewCount == 2)
        #expect(saved.updatedAt == originalUpdatedAt)
        #expect(ResurfacingService.isDue(saved, now: now))
        #expect(saved.title == "A quotation")
        #expect(saved.text == "Content")
        #expect(saved.source == "Conversation")
        #expect(saved.status == .organized)
        #expect(saved.topics.map(\.id) == [topic.id])
        #expect(saved.attributions.map(\.id) == [attribution.id])
        #expect(saved.reflections.map(\.id) == [reflection.id])

        let goodAt = now.addingTimeInterval(300)
        try ResurfacingService.markGood(saved, at: goodAt, calendar: calendar)
        try container.mainContext.save()
        saved = try #require(refetch(Material.self, from: container).first)

        #expect(saved.reviewCount == 3)
        #expect(saved.lastReviewedAt == goodAt)
        #expect(saved.nextReviewAt == calendar.date(byAdding: .day, value: 7, to: goodAt))
        #expect(saved.updatedAt == originalUpdatedAt)
        #expect(saved.status == .organized)
        #expect(saved.topics.map(\.id) == [topic.id])
        #expect(saved.attributions.map(\.id) == [attribution.id])
        #expect(saved.reflections.map(\.id) == [reflection.id])
        #expect(try refetch(Person.self, from: container).map(\.id) == [person.id])
        #expect(try refetch(Topic.self, from: container).map(\.id) == [topic.id])
        #expect(try refetch(Reflection.self, from: container).map(\.id) == [reflection.id])
    }

    @Test("Due Now and Schedule Date override only nextReviewAt, then Good resumes the stage")
    func manualOverridesPreserveStageAndInboxStatus() throws {
        let (container, context) = try makeStore()
        let calendar = testCalendar()
        let now = testNow(calendar: calendar)
        let priorReview = now.addingTimeInterval(-50_000)
        let material = try NoteService.quickCapture(text: "Inbox Material", now: now, in: context)
        material.reviewCount = 3
        material.lastReviewedAt = priorReview
        let originalUpdatedAt = material.updatedAt
        try context.save()

        let dueNow = now.addingTimeInterval(60)
        ResurfacingService.makeDueNow(material, at: dueNow)
        #expect(material.nextReviewAt == dueNow)
        #expect(material.lastReviewedAt == priorReview)
        #expect(material.reviewCount == 3)
        #expect(material.status == .inbox)

        let manualDate = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 3, hour: 17, minute: 21)
        ))
        ResurfacingService.schedule(material, on: manualDate)
        try context.save()

        var saved = try #require(refetch(Material.self, from: container).first)
        #expect(saved.nextReviewAt == manualDate)
        #expect(saved.lastReviewedAt == priorReview)
        #expect(saved.reviewCount == 3)
        #expect(saved.status == .inbox)
        #expect(saved.topics.isEmpty)
        #expect(saved.updatedAt == originalUpdatedAt)

        try ResurfacingService.markGood(saved, at: manualDate, calendar: calendar)
        try container.mainContext.save()
        saved = try #require(refetch(Material.self, from: container).first)
        #expect(saved.reviewCount == 4)
        #expect(saved.lastReviewedAt == manualDate)
        #expect(saved.nextReviewAt == calendar.date(byAdding: .day, value: 14, to: manualDate))
        #expect(saved.status == .inbox)
        #expect(saved.topics.isEmpty)
    }

    @Test("Startup reconciliation schedules only supported active legacy Materials and is idempotent")
    func reconciliationIsSafeAndIdempotent() throws {
        let (_, context) = try makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let originalUpdatedAt = now.addingTimeInterval(-20_000)
        let previousReview = now.addingTimeInterval(-10_000)
        let futureDate = now.addingTimeInterval(86_400)

        let freshLegacy = Material(
            type: .note,
            text: "Fresh legacy",
            updatedAt: originalUpdatedAt,
            nextReviewAt: nil
        )
        let experiencedLegacy = Material(
            type: .note,
            text: "Experienced legacy",
            updatedAt: originalUpdatedAt,
            lastReviewedAt: previousReview,
            nextReviewAt: nil,
            reviewCount: 4
        )
        let archived = Material(
            type: .note,
            text: "Archived legacy",
            updatedAt: originalUpdatedAt,
            nextReviewAt: nil,
            isArchived: true
        )
        let future = Material(
            type: .note,
            text: "Already scheduled",
            updatedAt: originalUpdatedAt,
            nextReviewAt: futureDate
        )
        let unsupported = Material(
            type: .note,
            text: "Unsupported",
            updatedAt: originalUpdatedAt,
            nextReviewAt: nil
        )
        unsupported.typeRawValue = "futureType"
        [freshLegacy, experiencedLegacy, archived, future, unsupported].forEach(context.insert)
        try context.save()

        let changed = try ResurfacingService.reconcileUnscheduledMaterials(in: context, now: now)
        #expect(changed == 2)
        #expect(freshLegacy.nextReviewAt == now)
        #expect(experiencedLegacy.nextReviewAt == now)
        #expect(experiencedLegacy.lastReviewedAt == previousReview)
        #expect(experiencedLegacy.reviewCount == 4)
        #expect(archived.nextReviewAt == nil)
        #expect(future.nextReviewAt == futureDate)
        #expect(unsupported.nextReviewAt == nil)
        #expect([freshLegacy, experiencedLegacy, archived, future, unsupported].allSatisfy {
            $0.updatedAt == originalUpdatedAt
        })

        let changedAgain = try ResurfacingService.reconcileUnscheduledMaterials(
            in: context,
            now: now.addingTimeInterval(500)
        )
        #expect(changedAgain == 0)
        #expect(freshLegacy.nextReviewAt == now)
        #expect(experiencedLegacy.nextReviewAt == now)
    }

    @Test("Today eligibility is read-only, complete, and deterministic")
    func todayEligibilityOrderingAndReadSafety() {
        let calendar = testCalendar()
        let now = testNow(calendar: calendar)
        let oldestDate = now.addingTimeInterval(-3_600)
        let tiedDate = now.addingTimeInterval(-60)
        let oldest = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
            type: .note,
            text: "Oldest",
            nextReviewAt: oldestDate,
            reviewCount: 2
        )
        let tiedFirst = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            type: .note,
            text: "Tie one",
            nextReviewAt: tiedDate
        )
        let tiedSecond = Material(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000043")!,
            type: .note,
            text: "Tie two",
            nextReviewAt: tiedDate
        )
        let dueExactlyNow = Material(type: .note, text: "Now", nextReviewAt: now)
        let future = Material(type: .note, text: "Future", nextReviewAt: now.addingTimeInterval(1))
        let archived = Material(type: .note, text: "Archived", nextReviewAt: oldestDate, isArchived: true)
        let unscheduled = Material(type: .note, text: "Unscheduled", nextReviewAt: nil)
        let unsupported = Material(type: .note, text: "Unsupported", nextReviewAt: oldestDate)
        unsupported.statusRawValue = "futureStatus"

        let originalLastReviewedAt = oldest.lastReviewedAt
        let originalReviewCount = oldest.reviewCount
        let first = ResurfacingService.dueMaterials(
            from: [tiedSecond, future, oldest, archived, tiedFirst, unscheduled, dueExactlyNow, unsupported, oldest],
            now: now,
            calendar: calendar
        )
        let second = ResurfacingService.dueMaterials(from: first, now: now, calendar: calendar)
        let expectedIDs = [oldest.id, tiedFirst.id, tiedSecond.id, dueExactlyNow.id]
        let firstIDs = first.map(\.id)
        let secondIDs = second.map(\.id)

        #expect(firstIDs == expectedIDs)
        #expect(secondIDs == firstIDs)
        #expect(!ResurfacingService.isDue(future, now: now))
        #expect(!ResurfacingService.isDue(archived, now: now))
        #expect(!ResurfacingService.isDue(unscheduled, now: now))
        #expect(!ResurfacingService.isDue(unsupported, now: now))
        #expect(oldest.lastReviewedAt == originalLastReviewedAt)
        #expect(oldest.nextReviewAt == oldestDate)
        #expect(oldest.reviewCount == originalReviewCount)
    }

    @Test("The transient queue rotates Again to the end and removes Good")
    func transientQueueBehavior() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let c = UUID(uuidString: "00000000-0000-0000-0000-000000000053")!
        var queue = MaterialReviewQueue(materialIDs: [a, b, c, a])

        #expect(queue.materialIDs == [a, b, c])
        #expect(queue.currentID == a)
        queue.markCurrentAgain()
        #expect(queue.materialIDs == [b, c, a])
        #expect(queue.remainingCount == 3)
        queue.markCurrentGood()
        #expect(queue.materialIDs == [c, a])
        queue.markCurrentGood()
        #expect(queue.materialIDs == [a])
        queue.markCurrentAgain()
        #expect(queue.materialIDs == [a])
        queue.markCurrentGood()
        #expect(queue.isEmpty)
    }
}
