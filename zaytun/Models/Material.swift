import Foundation
import SwiftData

@Model
final class Material {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var statusRawValue: String
    var title: String?
    var text: String?
    var mediaFilename: String?
    var contentTypeIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var capturedAt: Date
    var source: String?
    var lastReviewedAt: Date?
    var nextReviewAt: Date?
    var reviewCount: Int
    var isArchived: Bool

    @Relationship(deleteRule: .nullify, inverse: \Topic.materials)
    var topics: [Topic]

    @Relationship(deleteRule: .nullify, inverse: \Reflection.materials)
    var reflections: [Reflection]

    @Relationship(deleteRule: .cascade, inverse: \MaterialAttribution.material)
    var attributions: [MaterialAttribution]

    init(
        id: UUID = UUID(),
        type: MaterialType,
        status: MaterialStatus = .inbox,
        title: String? = nil,
        text: String? = nil,
        mediaFilename: String? = nil,
        contentTypeIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        capturedAt: Date = .now,
        source: String? = nil,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date? = nil,
        reviewCount: Int = 0,
        isArchived: Bool = false,
        topics: [Topic] = [],
        reflections: [Reflection] = [],
        attributions: [MaterialAttribution] = []
    ) {
        self.id = id
        self.typeRawValue = type.rawValue
        self.statusRawValue = status.rawValue
        self.title = title
        self.text = text
        self.mediaFilename = mediaFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.capturedAt = capturedAt
        self.source = source
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.reviewCount = reviewCount
        self.isArchived = isArchived
        self.topics = topics
        self.reflections = reflections
        self.attributions = attributions
    }

    var type: MaterialType? {
        get { MaterialType(rawValue: typeRawValue) }
        set {
            guard let newValue else { return }
            typeRawValue = newValue.rawValue
        }
    }

    var status: MaterialStatus? {
        get { MaterialStatus(rawValue: statusRawValue) }
        set {
            guard let newValue else { return }
            statusRawValue = newValue.rawValue
        }
    }

    var displayTitle: String {
        if let title = title?.trimmedNonempty {
            return title
        }
        if type == .note, let text = text?.trimmedNonempty {
            return String(text.prefix(60))
        }
        return String(localized: "Untitled Material")
    }

    var attributionSummary: String? {
        let values = attributions
            .sorted {
                let left = AttributionRole.supported.firstIndex(of: $0.role) ?? Int.max
                let right = AttributionRole.supported.firstIndex(of: $1.role) ?? Int.max
                return left == right ? $0.createdAt < $1.createdAt : left < right
            }
            .map { "\($0.role.displayName) \($0.person.displayName)" }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

extension String {
    var trimmedNonempty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
