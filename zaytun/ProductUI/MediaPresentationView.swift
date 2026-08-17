import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit

@MainActor
private enum MediaPlaybackAudioSession {
    static let failureMessage = "Audio playback could not start. Check the device volume and audio output, then try again."

    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }
}

struct MediaContentView: View {
    let material: Material
    var imageMaximumHeight: CGFloat? = nil
    var videoHeight: CGFloat = 280

    private var mediaURL: URL? {
        guard let storage = try? MediaStorageService.applicationSupport() else {
            return nil
        }
        return storage.existingURL(for: material.mediaFilename)
    }

    var body: some View {
        Group {
            if let mediaURL {
                switch material.type {
                case .image:
                    LocalImageView(url: mediaURL, maximumHeight: imageMaximumHeight)
                case .audio:
                    NativeAudioPlayerView(url: mediaURL)
                case .video:
                    NativeVideoPlayerView(url: mediaURL)
                        .frame(height: videoHeight)
                case .note, .none:
                    unavailable
                }
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Media file unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("The Material and its relationships are still available.")
        )
    }
}

private struct LocalImageView: View {
    let url: URL
    let maximumHeight: CGFloat?

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: maximumHeight)
                .accessibilityLabel("Image Material")
        } else {
            ContentUnavailableView(
                "Media file unavailable",
                systemImage: "photo.badge.exclamationmark"
            )
        }
    }
}

@MainActor
private final class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var loadError: String?
    @Published private(set) var playbackError: String?

    private var player: AVAudioPlayer?

    init(url: URL) {
        super.init()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = 1
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        } catch {
            loadError = error.localizedDescription
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            do {
                try MediaPlaybackAudioSession.activate()
                guard player.play() else {
                    playbackError = MediaPlaybackAudioSession.failureMessage
                    refresh()
                    return
                }
                playbackError = nil
            } catch {
                playbackError = MediaPlaybackAudioSession.failureMessage
            }
        }
        refresh()
    }

    func seek(to value: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(value, 0), player.duration)
        refresh()
    }

    func refresh() {
        guard let player else { return }
        currentTime = player.currentTime
        isPlaying = player.isPlaying
    }

    func pause() {
        player?.pause()
        refresh()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        refresh()
    }
}

private struct NativeAudioPlayerView: View {
    @StateObject private var model: AudioPlayerModel
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(url: URL) {
        _model = StateObject(wrappedValue: AudioPlayerModel(url: url))
    }

    var body: some View {
        if let loadError = model.loadError {
            ContentUnavailableView(
                "Audio unavailable",
                systemImage: "waveform.badge.exclamationmark",
                description: Text(loadError)
            )
        } else {
            VStack(spacing: 14) {
                Button(action: model.togglePlayback) {
                    Label(
                        model.isPlaying ? "Pause" : "Play",
                        systemImage: model.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let playbackError = model.playbackError {
                    Label(playbackError, systemImage: "speaker.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { model.currentTime },
                        set: { model.seek(to: $0) }
                    ),
                    in: 0...max(model.duration, 0.1)
                )
                .accessibilityLabel("Audio position")

                HStack {
                    Text(formatted(model.currentTime))
                    Spacer()
                    Text(formatted(model.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .onReceive(timer) { _ in model.refresh() }
            .onDisappear(perform: model.pause)
        }
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let value = interval.isFinite ? max(0, Int(interval)) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct NativeVideoPlayerView: View {
    @State private var player: AVPlayer
    @State private var playbackError: String?

    init(url: URL) {
        let player = AVPlayer(url: url)
        player.isMuted = false
        player.volume = 1
        _player = State(initialValue: player)
    }

    var body: some View {
        VideoPlayer(player: player)
            .accessibilityLabel("Video Material")
            .overlay(alignment: .bottom) {
                if let playbackError {
                    Label(playbackError, systemImage: "speaker.slash")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(8)
                }
            }
            .onAppear(perform: prepareForPlayback)
            .onDisappear { player.pause() }
    }

    private func prepareForPlayback() {
        do {
            try MediaPlaybackAudioSession.activate()
            player.isMuted = false
            player.volume = 1
            playbackError = nil
        } catch {
            playbackError = MediaPlaybackAudioSession.failureMessage
        }
    }
}

struct MaterialThumbnailView: View {
    let material: Material
    var size: CGFloat = 52

    private var image: UIImage? {
        guard material.type == .image,
              let storage = try? MediaStorageService.applicationSupport(),
              let url = storage.existingURL(for: material.mediaFilename) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private var systemImage: String {
        switch material.type {
        case .image: "photo"
        case .audio: "waveform"
        case .video: "video"
        case .note, .none: "doc.text"
        }
    }
}
