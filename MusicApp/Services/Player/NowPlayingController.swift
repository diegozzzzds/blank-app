import Foundation
import MediaPlayer
import UIKit

/// Lock screen / Control Center integration.
@MainActor
final class NowPlayingController {
    struct Handlers {
        var play: @MainActor () -> Void
        var pause: @MainActor () -> Void
        var toggle: @MainActor () -> Void
        var next: @MainActor () -> Void
        var previous: @MainActor () -> Void
        var seek: @MainActor (TimeInterval) -> Void
    }

    private var info: [String: Any] = [:]
    private var currentTrackID: String?
    private var configured = false

    func configureRemoteCommands(_ handlers: Handlers) {
        guard !configured else { return }
        configured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            Task { @MainActor in handlers.play() }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in handlers.pause() }
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in handlers.toggle() }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.next() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in handlers.seek(position) }
            return .success
        }
        // With skip commands enabled, the lock screen shows ±15s buttons instead of previous/next.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    /// Full update when the track changes.
    func update(track: PlayableTrack, duration: TimeInterval, elapsed: TimeInterval, rate: Float) {
        if currentTrackID != track.id {
            info = [:]
            currentTrackID = track.id
        }
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album ?? ""
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        applyPlayback(duration: duration, elapsed: elapsed, rate: rate)
    }

    /// Call only on play, pause, seek or duration changes; the system extrapolates elapsed time in between.
    func updatePlayback(duration: TimeInterval, elapsed: TimeInterval, rate: Float) {
        guard currentTrackID != nil else { return }
        applyPlayback(duration: duration, elapsed: elapsed, rate: rate)
    }

    func setArtwork(_ image: UIImage, forTrackID id: String) {
        guard id == currentTrackID else { return }
        info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        info = [:]
        currentTrackID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func applyPlayback(duration: TimeInterval, elapsed: TimeInterval, rate: Float) {
        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed.isFinite ? max(0, elapsed) : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Built outside the main actor on purpose: the request handler runs on a background queue,
    /// and a closure formed in a @MainActor context would trip Swift 6's isolation check.
    nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
