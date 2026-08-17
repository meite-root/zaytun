import Foundation
import UniformTypeIdentifiers

enum AppGroupConfiguration {
    static let identifier = "group.com.hassanemeite.zaytun.shared"
    static let importQueueDirectoryName = "ImportQueue"
}

enum SharedMediaKind: String, Codable, CaseIterable, Sendable {
    case image
    case audio
    case video

    static func detect(contentType: UTType) -> SharedMediaKind? {
        if contentType.conforms(to: .image) {
            return .image
        }
        if contentType.conforms(to: .audio) {
            return .audio
        }
        if contentType.conforms(to: .movie)
            || contentType.conforms(to: .audiovisualContent) {
            return .video
        }
        return nil
    }

    static func detect(typeIdentifiers: [String]) -> (SharedMediaKind, UTType)? {
        for identifier in typeIdentifiers {
            guard let contentType = UTType(identifier),
                  let kind = detect(contentType: contentType) else {
                continue
            }
            return (kind, contentType)
        }
        return nil
    }
}

struct SharedImportManifest: Codable, Equatable, Sendable {
    let importID: UUID
    let mediaKind: SharedMediaKind
    let stagedFilename: String
    let originalFilename: String?
    let createdAt: Date
    let contentTypeIdentifier: String
}

struct SharedImportEntry: Equatable, Sendable {
    let directoryURL: URL
    let payloadURL: URL
    let manifest: SharedImportManifest
}

enum SharedImportQueueError: LocalizedError, Equatable {
    case appGroupUnavailable
    case unsupportedContentType(String)
    case invalidManifest
    case missingPayload
    case unsafeFilename

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "Zaytun's shared import container is unavailable."
        case .unsupportedContentType:
            "That item is not a supported image, audio, or video file."
        case .invalidManifest:
            "A shared import manifest is invalid."
        case .missingPayload:
            "A shared import is missing its media file."
        case .unsafeFilename:
            "A shared import contains an unsafe filename."
        }
    }
}

struct SharedImportQueue: Sendable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func appGroup(fileManager: FileManager = .default) throws -> SharedImportQueue {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfiguration.identifier
        ) else {
            throw SharedImportQueueError.appGroupUnavailable
        }
        return SharedImportQueue(
            rootURL: containerURL.appending(
                path: AppGroupConfiguration.importQueueDirectoryName,
                directoryHint: .isDirectory
            )
        )
    }

    @discardableResult
    func stage(
        sourceURL: URL,
        contentType: UTType,
        originalFilename: String? = nil,
        importID: UUID = UUID(),
        createdAt: Date = .now,
        fileManager: FileManager = .default
    ) throws -> SharedImportEntry {
        guard let kind = SharedMediaKind.detect(contentType: contentType) else {
            throw SharedImportQueueError.unsupportedContentType(contentType.identifier)
        }

        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let finalDirectory = rootURL.appending(path: importID.uuidString, directoryHint: .isDirectory)
        let stagingDirectory = rootURL.appending(
            path: ".\(importID.uuidString).staging",
            directoryHint: .isDirectory
        )
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)

        do {
            let filename = payloadFilename(
                contentType: contentType,
                originalFilename: originalFilename ?? sourceURL.lastPathComponent
            )
            let stagedPayload = stagingDirectory.appending(path: filename)
            try fileManager.copyItem(at: sourceURL, to: stagedPayload)

            let manifest = SharedImportManifest(
                importID: importID,
                mediaKind: kind,
                stagedFilename: filename,
                originalFilename: originalFilename?.nonemptyFilename,
                createdAt: createdAt,
                contentTypeIdentifier: contentType.identifier
            )
            let manifestData = try JSONEncoder.zaytun.encode(manifest)
            try manifestData.write(
                to: stagingDirectory.appending(path: "manifest.json"),
                options: .atomic
            )

            if fileManager.fileExists(atPath: finalDirectory.path) {
                try fileManager.removeItem(at: finalDirectory)
            }
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
            return SharedImportEntry(
                directoryURL: finalDirectory,
                payloadURL: finalDirectory.appending(path: filename),
                manifest: manifest
            )
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    func entries(fileManager: FileManager = .default) throws -> [SharedImportEntry] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let directoryURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try directoryURLs.compactMap { directoryURL in
            let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            return try entry(at: directoryURL, fileManager: fileManager)
        }
        .sorted {
            if $0.manifest.createdAt != $1.manifest.createdAt {
                return $0.manifest.createdAt < $1.manifest.createdAt
            }
            return $0.manifest.importID.uuidString < $1.manifest.importID.uuidString
        }
    }

    func remove(_ entry: SharedImportEntry, fileManager: FileManager = .default) throws {
        guard entry.directoryURL.deletingLastPathComponent().standardizedFileURL
            == rootURL.standardizedFileURL else {
            throw SharedImportQueueError.invalidManifest
        }
        if fileManager.fileExists(atPath: entry.directoryURL.path) {
            try fileManager.removeItem(at: entry.directoryURL)
        }
    }

    private func entry(
        at directoryURL: URL,
        fileManager: FileManager
    ) throws -> SharedImportEntry {
        let manifestURL = directoryURL.appending(path: "manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SharedImportQueueError.invalidManifest
        }
        let manifest = try JSONDecoder.zaytun.decode(
            SharedImportManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard directoryURL.lastPathComponent == manifest.importID.uuidString else {
            throw SharedImportQueueError.invalidManifest
        }
        guard manifest.stagedFilename.nonemptyFilename == manifest.stagedFilename else {
            throw SharedImportQueueError.unsafeFilename
        }
        guard let contentType = UTType(manifest.contentTypeIdentifier),
              SharedMediaKind.detect(contentType: contentType) == manifest.mediaKind else {
            throw SharedImportQueueError.unsupportedContentType(manifest.contentTypeIdentifier)
        }
        let payloadURL = directoryURL.appending(path: manifest.stagedFilename)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw SharedImportQueueError.missingPayload
        }
        return SharedImportEntry(
            directoryURL: directoryURL,
            payloadURL: payloadURL,
            manifest: manifest
        )
    }

    private func payloadFilename(
        contentType: UTType,
        originalFilename: String?
    ) -> String {
        let originalExtension = originalFilename
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 }
        let filenameExtension = originalExtension
            ?? contentType.preferredFilenameExtension
        if let filenameExtension {
            return "payload.\(filenameExtension.lowercased())"
        }
        return "payload"
    }
}

private extension String {
    var nonemptyFilename: String? {
        guard !isEmpty,
              self == URL(fileURLWithPath: self).lastPathComponent,
              self != ".",
              self != ".." else {
            return nil
        }
        return self
    }
}

private extension JSONEncoder {
    static var zaytun: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var zaytun: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
