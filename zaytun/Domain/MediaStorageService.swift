import Foundation
import UniformTypeIdentifiers

struct MediaStorageDeletion: Equatable, Sendable {
    let originalURL: URL
    let stagedURL: URL
}

enum MediaStorageError: LocalizedError, Equatable {
    case applicationSupportUnavailable
    case unsafeFilename
    case destinationExists
    case missingSource

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Zaytun could not access its media storage directory."
        case .unsafeFilename:
            "The stored media filename is invalid."
        case .destinationExists:
            "A media file with that internal identity already exists."
        case .missingSource:
            "The selected media file is no longer available."
        }
    }
}

struct MediaStorageService: Sendable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> MediaStorageService {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MediaStorageError.applicationSupportUnavailable
        }
        return MediaStorageService(
            rootURL: applicationSupport
                .appending(path: "Zaytun", directoryHint: .isDirectory)
                .appending(path: "Media", directoryHint: .isDirectory)
        )
    }

    func storedFilename(
        materialID: UUID,
        contentType: UTType,
        originalFilename: String? = nil
    ) -> String {
        let originalExtension = originalFilename
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0.lowercased() }
        let compatibleOriginalExtension = originalExtension.flatMap { value -> String? in
            guard let originalType = UTType(filenameExtension: value),
                  originalType.conforms(to: contentType)
                    || contentType.conforms(to: originalType) else {
                return nil
            }
            return value
        }
        let filenameExtension = compatibleOriginalExtension
            ?? contentType.preferredFilenameExtension
        if let filenameExtension {
            return "\(materialID.uuidString).\(filenameExtension.lowercased())"
        }
        return materialID.uuidString
    }

    @discardableResult
    func copyIntoStorage(
        from sourceURL: URL,
        materialID: UUID,
        contentType: UTType,
        originalFilename: String? = nil,
        replaceExisting: Bool = false,
        fileManager: FileManager = .default
    ) throws -> String {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw MediaStorageError.missingSource
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let filename = storedFilename(
            materialID: materialID,
            contentType: contentType,
            originalFilename: originalFilename
        )
        let destinationURL = try url(for: filename)
        if fileManager.fileExists(atPath: destinationURL.path) {
            guard replaceExisting else { throw MediaStorageError.destinationExists }
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return filename
    }

    func url(for filename: String) throws -> URL {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.isEmpty,
              filename != ".",
              filename != ".." else {
            throw MediaStorageError.unsafeFilename
        }
        return rootURL.appending(path: filename)
    }

    func existingURL(
        for filename: String?,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let filename,
              let fileURL = try? url(for: filename),
              fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return fileURL
    }

    func removeFile(
        named filename: String,
        fileManager: FileManager = .default
    ) throws {
        let fileURL = try url(for: filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func stageDeletion(
        of filename: String?,
        fileManager: FileManager = .default
    ) throws -> MediaStorageDeletion? {
        guard let filename,
              let originalURL = existingURL(for: filename, fileManager: fileManager) else {
            return nil
        }
        let trashURL = rootURL.appending(path: ".DeletionStaging", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: trashURL, withIntermediateDirectories: true)
        let stagedURL = trashURL.appending(path: "\(UUID().uuidString)-\(filename)")
        try fileManager.moveItem(at: originalURL, to: stagedURL)
        return MediaStorageDeletion(originalURL: originalURL, stagedURL: stagedURL)
    }

    func restoreDeletion(
        _ deletion: MediaStorageDeletion,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: deletion.stagedURL.path) else { return }
        if fileManager.fileExists(atPath: deletion.originalURL.path) {
            try fileManager.removeItem(at: deletion.originalURL)
        }
        try fileManager.moveItem(at: deletion.stagedURL, to: deletion.originalURL)
    }

    func commitDeletion(
        _ deletion: MediaStorageDeletion,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: deletion.stagedURL.path) {
            try fileManager.removeItem(at: deletion.stagedURL)
        }
    }
}
