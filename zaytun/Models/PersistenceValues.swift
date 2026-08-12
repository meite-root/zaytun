import Foundation

enum MaterialType: String, CaseIterable, Identifiable {
    case note
    case image
    case audio
    case video

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .note: String(localized: "Note")
        case .image: String(localized: "Image")
        case .audio: String(localized: "Audio")
        case .video: String(localized: "Video")
        }
    }
}

enum MaterialStatus: String, CaseIterable, Identifiable {
    case inbox
    case organized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inbox: String(localized: "Inbox")
        case .organized: String(localized: "Organized")
        }
    }
}

enum ReflectionKind: String, CaseIterable, Identifiable {
    case thought
    case question
    case synthesis

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thought: String(localized: "Thought")
        case .question: String(localized: "Question")
        case .synthesis: String(localized: "Synthesis")
        }
    }
}

/// A value wrapper around the persisted role string. Unknown future values stay intact.
struct AttributionRole: RawRepresentable, Hashable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    static let createdBy = AttributionRole(rawValue: "createdBy")
    static let saidBy = AttributionRole(rawValue: "saidBy")
    static let sharedBy = AttributionRole(rawValue: "sharedBy")

    static let supported: [AttributionRole] = [.createdBy, .saidBy, .sharedBy]

    var isSupported: Bool {
        Self.supported.contains(self)
    }

    var displayName: String {
        switch self {
        case .createdBy: String(localized: "Created by")
        case .saidBy: String(localized: "Said by")
        case .sharedBy: String(localized: "Shared by")
        default: String(localized: "Unsupported role")
        }
    }
}
