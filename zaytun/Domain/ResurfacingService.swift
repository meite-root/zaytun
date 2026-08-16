import Foundation
import SwiftData

enum ResurfacingError: LocalizedError, Equatable {
    case dateCalculationFailed

    var errorDescription: String? {
        String(localized: "Zaytun could not calculate that review date.")
    }
}

@MainActor
enum ResurfacingService {
    /// Returns every supported, active Material whose persisted review date has arrived.
    static func dueMaterials(
        from materials: [Material],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Material] {
        var materialsByID: [UUID: Material] = [:]
        for material in materials where isDue(material, now: now) {
            materialsByID[material.id] = material
        }

        return materialsByID.values.sorted { left, right in
            guard let leftDate = left.nextReviewAt,
                  let rightDate = right.nextReviewAt else {
                return left.id.uuidString < right.id.uuidString
            }
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    static func isDue(_ material: Material, now: Date = .now) -> Bool {
        guard isSupportedAndActive(material),
              let nextReviewAt = material.nextReviewAt else {
            return false
        }
        return nextReviewAt <= now
    }

    /// `reviewCount` is the successful-review stage. The returned value is in calendar days.
    static func intervalAfterSuccessfulReview(_ successfulReviewCount: Int) -> Int {
        switch successfulReviewCount {
        case ...1: 1
        case 2: 3
        case 3: 7
        case 4: 14
        case 5: 30
        case 6: 60
        default: 90
        }
    }

    static func nextReviewDate(
        afterSuccessfulReviewCount successfulReviewCount: Int,
        from now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Date {
        guard let date = calendar.date(
            byAdding: .day,
            value: intervalAfterSuccessfulReview(successfulReviewCount),
            to: now
        ) else {
            throw ResurfacingError.dateCalculationFailed
        }
        return date
    }

    static func markGood(
        _ material: Material,
        at now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let nextCount = material.reviewCount < Int.max
            ? material.reviewCount + 1
            : Int.max
        let nextDate = try nextReviewDate(
            afterSuccessfulReviewCount: nextCount,
            from: now,
            calendar: calendar
        )

        material.lastReviewedAt = now
        material.reviewCount = nextCount
        material.nextReviewAt = nextDate
    }

    /// Again records the attempt without advancing the successful-review stage.
    static func markAgain(_ material: Material, at now: Date = .now) {
        material.lastReviewedAt = now
        material.nextReviewAt = now
    }

    /// Manual overrides intentionally change only the next due date.
    static func makeDueNow(_ material: Material, at now: Date = .now) {
        material.nextReviewAt = now
    }

    /// Manual overrides intentionally change only the next due date.
    static func schedule(_ material: Material, on date: Date) {
        material.nextReviewAt = date
    }

    /// Makes legacy active Materials participate in review without changing content or history.
    @discardableResult
    static func reconcileUnscheduledMaterials(
        in context: ModelContext,
        now: Date = .now
    ) throws -> Int {
        let materials = try context.fetch(FetchDescriptor<Material>())
        let unscheduled = materials.filter {
            isSupportedAndActive($0) && $0.nextReviewAt == nil
        }

        for material in unscheduled {
            material.nextReviewAt = now
        }
        if !unscheduled.isEmpty {
            try context.save()
        }
        return unscheduled.count
    }

    private static func isSupportedAndActive(_ material: Material) -> Bool {
        !material.isArchived && material.type != nil && material.status != nil
    }
}

/// The Today session is intentionally transient. Only review state is persisted on Material.
struct MaterialReviewQueue: Equatable {
    private(set) var materialIDs: [UUID]

    init(materialIDs: [UUID] = []) {
        var seen: Set<UUID> = []
        self.materialIDs = materialIDs.filter { seen.insert($0).inserted }
    }

    var currentID: UUID? { materialIDs.first }
    var remainingCount: Int { materialIDs.count }
    var isEmpty: Bool { materialIDs.isEmpty }

    mutating func refresh(with orderedDueIDs: [UUID]) {
        let dueIDs = Set(orderedDueIDs)
        materialIDs.removeAll { !dueIDs.contains($0) }

        var existing = Set(materialIDs)
        materialIDs.append(contentsOf: orderedDueIDs.filter { existing.insert($0).inserted })
    }

    mutating func markCurrentGood() {
        guard !materialIDs.isEmpty else { return }
        materialIDs.removeFirst()
    }

    mutating func markCurrentAgain() {
        guard !materialIDs.isEmpty else { return }
        materialIDs.append(materialIDs.removeFirst())
    }
}
