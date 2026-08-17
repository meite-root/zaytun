import AVFoundation
import Foundation
import Speech
import SwiftData
import Vision

nonisolated enum MediaUnderstandingOperation: Equatable, Sendable {
    case imageRecognition
    case audioTranscription
    case videoTranscription
}

enum SpeechRecognitionAuthorization: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case unavailable
}

nonisolated enum MediaUnderstandingError: LocalizedError, Equatable {
    case unsupportedMaterial
    case mediaUnavailable
    case alreadyProcessing
    case textRecognitionFailed
    case transcriptionUnavailable
    case speechPermissionDenied
    case speechPermissionRestricted
    case noAudioTrack
    case mediaTooLong
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedMaterial:
            "Media understanding is not available for this Material."
        case .mediaUnavailable:
            "The media file is unavailable."
        case .alreadyProcessing:
            "Media understanding is already in progress."
        case .textRecognitionFailed:
            "Text recognition failed. Try again."
        case .transcriptionUnavailable:
            "Transcription is unavailable. Try again later."
        case .speechPermissionDenied:
            "Speech Recognition permission is required. Enable it for Zaytun in Settings, then try again."
        case .speechPermissionRestricted:
            "Speech Recognition is restricted on this device."
        case .noAudioTrack:
            "This video does not contain an audio track to transcribe."
        case .mediaTooLong:
            "Transcription currently supports media up to one minute."
        case .persistenceFailed:
            "Zaytun could not save the recognized text."
        }
    }
}

nonisolated protocol MediaUnderstandingProcessing: Sendable {
    nonisolated func recognizeText(in imageURL: URL) async throws -> String?
    nonisolated func transcribeAudio(at audioURL: URL, locale: Locale) async throws -> String?
    nonisolated func transcribeVideo(at videoURL: URL, locale: Locale) async throws -> String?
}

struct NativeMediaUnderstandingProcessor: MediaUnderstandingProcessing {
    nonisolated init() {}

    nonisolated func recognizeText(in imageURL: URL) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(url: imageURL)
            try handler.perform([request])
            try Task.checkCancellation()

            let observations = (request.results ?? []).sorted { left, right in
                let verticalDifference = abs(left.boundingBox.midY - right.boundingBox.midY)
                if verticalDifference > 0.02 {
                    return left.boundingBox.midY > right.boundingBox.midY
                }
                return left.boundingBox.minX < right.boundingBox.minX
            }
            let lines = observations.compactMap {
                $0.topCandidates(1).first?.string.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }.filter { !$0.isEmpty }

            return normalizedExtractedText(lines.joined(separator: "\n"))
        }.value
    }

    nonisolated func transcribeAudio(
        at audioURL: URL,
        locale: Locale
    ) async throws -> String? {
        try await validateSpeechDuration(at: audioURL)
        return try await transcribeSpeechFile(at: audioURL, locale: locale)
    }

    nonisolated func transcribeVideo(
        at videoURL: URL,
        locale: Locale
    ) async throws -> String? {
        try await validateSpeechDuration(at: videoURL)

        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw MediaUnderstandingError.noAudioTrack
        }
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MediaUnderstandingError.transcriptionUnavailable
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "Zaytun-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try await exporter.export(to: temporaryURL, as: .m4a)
            try Task.checkCancellation()
            return try await transcribeSpeechFile(at: temporaryURL, locale: locale)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MediaUnderstandingError {
            throw error
        } catch {
            throw MediaUnderstandingError.transcriptionUnavailable
        }
    }

    private nonisolated func validateSpeechDuration(at url: URL) async throws {
        let duration = try await AVURLAsset(url: url).load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite else {
            throw MediaUnderstandingError.transcriptionUnavailable
        }
        guard seconds <= 60 else {
            throw MediaUnderstandingError.mediaTooLong
        }
    }

    private nonisolated func transcribeSpeechFile(
        at url: URL,
        locale: Locale
    ) async throws -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw MediaUnderstandingError.transcriptionUnavailable
        }
        guard recognizer.isAvailable else {
            throw MediaUnderstandingError.transcriptionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let session = SpeechRecognitionSession(recognizer: recognizer)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                session.install(continuation: continuation)
                guard !session.isFinished else { return }

                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        session.finish(throwing: error)
                    } else if let result, result.isFinal {
                        session.finish(
                            returning: normalizedExtractedText(
                                result.bestTranscription.formattedString
                            )
                        )
                    }
                }
                session.install(task: task)
            }
        } onCancel: {
            session.cancel()
        }
    }
}

@MainActor
enum MediaUnderstandingService {
    typealias SaveAction = (ModelContext) throws -> Void

    private static var activeMaterialIDs: Set<UUID> = []

    static func operation(for material: Material) throws -> MediaUnderstandingOperation {
        switch material.type {
        case .image: .imageRecognition
        case .audio: .audioTranscription
        case .video: .videoTranscription
        case .note, .none: throw MediaUnderstandingError.unsupportedMaterial
        }
    }

    static func requestSpeechAuthorization() async -> SpeechRecognitionAuthorization {
        let current = SFSpeechRecognizer.authorizationStatus()
        let status: SFSpeechRecognizerAuthorizationStatus
        if current == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { authorization in
                    continuation.resume(returning: authorization)
                }
            }
        } else {
            status = current
        }

        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .unavailable
        @unknown default: return .unavailable
        }
    }

    @discardableResult
    static func process(
        _ material: Material,
        storage: MediaStorageService,
        processor: any MediaUnderstandingProcessing = NativeMediaUnderstandingProcessor(),
        locale: Locale = .current,
        now: Date = .now,
        in context: ModelContext,
        save: SaveAction? = nil
    ) async throws -> String? {
        let operation = try operation(for: material)
        guard activeMaterialIDs.insert(material.id).inserted else {
            throw MediaUnderstandingError.alreadyProcessing
        }
        defer { activeMaterialIDs.remove(material.id) }

        guard let mediaURL = storage.existingURL(for: material.mediaFilename) else {
            throw MediaUnderstandingError.mediaUnavailable
        }

        let extractedText: String?
        do {
            switch operation {
            case .imageRecognition:
                extractedText = try await processor.recognizeText(in: mediaURL)
            case .audioTranscription:
                extractedText = try await processor.transcribeAudio(
                    at: mediaURL,
                    locale: locale
                )
            case .videoTranscription:
                extractedText = try await processor.transcribeVideo(
                    at: mediaURL,
                    locale: locale
                )
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MediaUnderstandingError {
            throw error
        } catch {
            throw operation == .imageRecognition
                ? MediaUnderstandingError.textRecognitionFailed
                : MediaUnderstandingError.transcriptionUnavailable
        }

        let normalized = normalizedExtractedText(extractedText)
        let previousText = material.extractedText
        let previousUpdatedAt = material.updatedAt
        material.extractedText = normalized
        material.updatedAt = now

        do {
            if let save {
                try save(context)
            } else {
                try context.save()
            }
        } catch {
            material.extractedText = previousText
            material.updatedAt = previousUpdatedAt
            throw MediaUnderstandingError.persistenceFailed
        }

        return normalized
    }

    static func startAutomaticImageRecognition(
        for material: Material,
        storage: MediaStorageService,
        in context: ModelContext
    ) {
        guard material.type == .image, material.extractedText == nil else { return }
        Task { @MainActor in
            do {
                _ = try await process(material, storage: storage, in: context)
            } catch MediaUnderstandingError.alreadyProcessing {
                // A user-triggered recognition request already owns this Material.
            } catch is CancellationError {
                // Automatic recognition is best-effort while the app remains active.
            } catch {
                print("Automatic image text recognition failed for \(material.id): \(error.localizedDescription)")
            }
        }
    }
}

private nonisolated func normalizedExtractedText(_ value: String?) -> String? {
    value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private nonisolated final class SpeechRecognitionSession: @unchecked Sendable {
    private let lock = NSLock()
    private let recognizer: SFSpeechRecognizer
    private var continuation: CheckedContinuation<String?, any Error>?
    private var task: SFSpeechRecognitionTask?
    private var finished = false

    init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    var isFinished: Bool {
        lock.withLock { finished }
    }

    func install(continuation: CheckedContinuation<String?, any Error>) {
        let shouldCancel = lock.withLock {
            if finished { return true }
            self.continuation = continuation
            return false
        }
        if shouldCancel {
            continuation.resume(throwing: CancellationError())
        }
    }

    func install(task: SFSpeechRecognitionTask) {
        let shouldCancel = lock.withLock {
            if finished { return true }
            self.task = task
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    func finish(returning value: String?) {
        complete(with: .success(value))
    }

    func finish(throwing error: any Error) {
        complete(with: .failure(error))
    }

    func cancel() {
        let values = lock.withLock { () -> (SFSpeechRecognitionTask?, CheckedContinuation<String?, any Error>?) in
            guard !finished else { return (nil, nil) }
            finished = true
            defer {
                task = nil
                continuation = nil
            }
            return (task, continuation)
        }
        values.0?.cancel()
        values.1?.resume(throwing: CancellationError())
    }

    private func complete(with result: Result<String?, any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<String?, any Error>? in
            guard !finished else { return nil }
            finished = true
            defer {
                task = nil
                self.continuation = nil
            }
            return self.continuation
        }
        continuation?.resume(with: result)
        _ = recognizer
    }
}
