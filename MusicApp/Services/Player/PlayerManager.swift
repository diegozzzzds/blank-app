import AVFoundation
import Foundation
import Observation
import UIKit

/// Plays the queue with AVPlayer and keeps the lock screen in sync.
/// Lives for the whole app lifetime (owned by `AppDependencies`).
@MainActor
@Observable
final class PlayerManager {
    private(set) var queue = PlayQueue()
    private(set) var currentTrack: PlayableTrack?
    /// True while playing or waiting to play (drives the play/pause button).
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: TimeInterval = 0
    /// Duration of the loaded item (30 s for iTunes previews).
    private(set) var duration: TimeInterval = 0
    /// Set by the progress slider while dragging so time updates don't fight the finger.
    var isScrubbing = false
    var errorMessage: String?

    var repeatMode: RepeatMode { queue.repeatMode }
    var isShuffled: Bool { queue.isShuffled }
    var hasTrack: Bool { currentTrack != nil }

    private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    private let audioSession: AudioSessionController
    private let nowPlaying: NowPlayingController
    private let artwork: ArtworkLoader
    private let files: FileLocations
    private let library: LibraryStore
    private let defaults: UserDefaults

    init(
        audioSession: AudioSessionController,
        nowPlaying: NowPlayingController,
        artwork: ArtworkLoader,
        files: FileLocations,
        library: LibraryStore,
        defaults: UserDefaults = .standard
    ) {
        self.audioSession = audioSession
        self.nowPlaying = nowPlaying
        self.artwork = artwork
        self.files = files
        self.library = library
        self.defaults = defaults

        if let raw = defaults.string(forKey: SettingsKey.repeatMode), let mode = RepeatMode(rawValue: raw) {
            queue.repeatMode = mode
        }
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        configureAudioSessionCallbacks()
        nowPlaying.configureRemoteCommands(NowPlayingController.Handlers(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] time in
                Task { await self?.seek(to: time) }
            }
        ))
    }

    // MARK: - Starting playback

    /// Replaces the queue and starts playing `tracks[index]`.
    func play(_ tracks: [PlayableTrack], startAt index: Int = 0, shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        queue.replace(with: tracks, startAt: index, shuffle: shuffle)
        consecutiveFailures = 0
        if let entry = queue.current {
            load(entry, autoplay: true)
        }
    }

    /// Inserts after the current track (or starts playing if nothing is queued).
    func playNext(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty || currentTrack == nil {
            play(tracks)
        } else {
            queue.insertNext(tracks)
        }
    }

    /// Appends to the end of the queue (or starts playing if nothing is queued).
    func addToQueue(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty || currentTrack == nil {
            play(tracks)
        } else {
            queue.append(tracks)
        }
    }

    // MARK: - Transport

    func play() {
        if player.currentItem == nil {
            guard let entry = queue.current else { return }
            load(entry, autoplay: true)
            return
        }
        audioSession.activate()
        player.play()
        syncNowPlayingPlayback(rate: 1)
    }

    func pause() {
        player.pause()
        syncNowPlayingPlayback(rate: 0)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func next() {
        guard let entry = queue.advance(automatic: false) else { return }
        consecutiveFailures = 0
        load(entry, autoplay: true)
    }

    /// Restarts the current song if more than 3 s have played, otherwise goes to the previous one.
    func previous() {
        if currentTime > 3 {
            Task { await seek(to: 0) }
            return
        }
        let before = queue.current?.id
        guard let entry = queue.goBack() else { return }
        if entry.id == before {
            Task { await seek(to: 0) }
        } else {
            consecutiveFailures = 0
            load(entry, autoplay: true)
        }
    }

    func seek(to seconds: TimeInterval) async {
        guard player.currentItem != nil, seconds.isFinite else { return }
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = target
        let time = CMTime(seconds: target, preferredTimescale: 600)
        _ = await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        syncNowPlayingPlayback(rate: isPlaying ? 1 : 0)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        detachItemObservers()
        queue.clear()
        currentTrack = nil
        currentTime = 0
        duration = 0
        nowPlaying.clear()
    }

    // MARK: - Modes

    func cycleRepeatMode() {
        queue.repeatMode = queue.repeatMode.next
        defaults.set(queue.repeatMode.rawValue, forKey: SettingsKey.repeatMode)
    }

    func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
    }

    // MARK: - Queue editing

    func jump(toUpNext index: Int) {
        guard let entry = queue.jump(toUpNext: index) else { return }
        consecutiveFailures = 0
        load(entry, autoplay: true)
    }

    func jump(toEntryID id: UUID) {
        guard queue.current?.id != id, let entry = queue.jump(toEntryID: id) else { return }
        consecutiveFailures = 0
        load(entry, autoplay: true)
    }

    func moveUpNext(from source: IndexSet, to destination: Int) {
        queue.moveUpNext(fromOffsets: source, toOffset: destination)
    }

    func removeUpNext(at offsets: IndexSet) {
        queue.removeUpNext(atOffsets: offsets)
    }

    func clearUpNext() {
        let count = queue.upNext.count
        guard count > 0 else { return }
        queue.removeUpNext(atOffsets: IndexSet(integersIn: 0..<count))
    }

    /// Called when a track's stored data changed (e.g. it was downloaded) so the queue uses the new copy.
    func trackDidChange(_ track: PlayableTrack) {
        queue.updateTrack(track)
        if currentTrack?.id == track.id {
            currentTrack = track
        }
    }

    /// Removes a deleted track from the queue; moves on if it was playing.
    func removeTrackEverywhere(_ id: String) {
        let wasCurrent = currentTrack?.id == id
        queue.removeTracks(withID: id)
        guard wasCurrent else { return }
        if let entry = queue.current {
            load(entry, autoplay: isPlaying)
        } else {
            stop()
        }
    }

    // MARK: - Loading

    private func load(_ entry: QueueEntry, autoplay: Bool) {
        var track = entry.track
        detachItemObservers()
        artworkTask?.cancel()

        guard let url = resolveURL(for: &track) else {
            currentTrack = track
            handleItemFailed(message: "「\(track.title)」没有可播放的地址")
            return
        }
        if track != entry.track {
            queue.updateTrack(track)
        }

        currentTrack = track
        currentTime = 0
        duration = track.isPreview ? 30 : (track.duration ?? 0)
        errorMessage = nil

        let item = AVPlayerItem(url: url)
        attachItemObservers(item)
        player.replaceCurrentItem(with: item)

        nowPlaying.update(track: track, duration: duration, elapsed: 0, rate: autoplay ? 1 : 0)
        loadArtwork(for: track)
        library.markPlayed(track.id)

        if autoplay {
            audioSession.activate()
            player.play()
        }
    }

    /// Local file if it still exists, otherwise the stream URL.
    private func resolveURL(for track: inout PlayableTrack) -> URL? {
        if let filename = track.localFilename {
            if files.musicFileExists(filename) {
                return files.musicURL(filename)
            }
            // The file was deleted (e.g. in the Files app): forget it and stream instead.
            track.localFilename = nil
            library.setLocalFile(nil, for: track.id)
        }
        return track.streamURL
    }

    private func loadArtwork(for track: PlayableTrack) {
        let loader = artwork
        artworkTask = Task { [weak self] in
            guard let image = await loader.image(for: track), !Task.isCancelled else { return }
            self?.nowPlaying.setArtwork(image, forTrackID: track.id)
        }
    }

    // MARK: - Observation

    private func observePlayer() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.handleTick(time)
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.handleTimeControlStatus(status)
            }
        }
    }

    private func attachItemObservers(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            let itemDuration = item.duration.seconds
            Task { @MainActor in
                self?.handleItemStatus(status, errorMessage: message, duration: itemDuration)
            }
        }
        let center = NotificationCenter.default
        itemObservers.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleItemEnded()
            }
        })
        itemObservers.append(center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let message = error?.localizedDescription
            MainActor.assumeIsolated {
                self?.handleItemFailed(message: message)
            }
        })
    }

    private func detachItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        for observer in itemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        itemObservers.removeAll()
    }

    private func handleTick(_ time: CMTime) {
        let seconds = time.seconds
        if !isScrubbing, seconds.isFinite {
            currentTime = max(0, seconds)
        }
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0,
           abs(itemDuration - duration) > 0.5 {
            duration = itemDuration
            syncNowPlayingPlayback(rate: isPlaying ? 1 : 0)
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        let playing = status != .paused
        let changed = playing != isPlaying
        isPlaying = playing
        isBuffering = status == .waitingToPlayAtSpecifiedRate
        if changed {
            syncNowPlayingPlayback(rate: playing ? 1 : 0)
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, errorMessage message: String?, duration itemDuration: Double) {
        switch status {
        case .readyToPlay:
            consecutiveFailures = 0
            if itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
                syncNowPlayingPlayback(rate: isPlaying ? 1 : 0)
            }
        case .failed:
            handleItemFailed(message: message)
        default:
            break
        }
    }

    private func handleItemEnded() {
        let finished = queue.current?.id
        guard let next = queue.advance(automatic: true) else {
            // End of the queue: rewind and stop.
            player.pause()
            player.seek(to: .zero)
            currentTime = 0
            syncNowPlayingPlayback(rate: 0)
            return
        }
        if next.id == finished {
            // Repeat one.
            player.seek(to: .zero)
            player.play()
            syncNowPlayingPlayback(rate: 1)
        } else {
            load(next, autoplay: true)
        }
    }

    private func handleItemFailed(message: String?) {
        consecutiveFailures += 1
        let title = currentTrack?.title ?? "歌曲"
        errorMessage = "无法播放「\(title)」" + (message.map { "：\($0)" } ?? "")
        // Skip ahead, but give up after a few failures in a row so a dead network doesn't spin forever.
        if consecutiveFailures < 3, let entry = queue.advance(automatic: false) {
            load(entry, autoplay: true)
        } else {
            player.pause()
            syncNowPlayingPlayback(rate: 0)
        }
    }

    private func configureAudioSessionCallbacks() {
        audioSession.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            self.wasPlayingBeforeInterruption = self.isPlaying
            self.syncNowPlayingPlayback(rate: 0)
        }
        audioSession.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            if shouldResume && self.wasPlayingBeforeInterruption {
                self.play()
            }
            self.wasPlayingBeforeInterruption = false
        }
        audioSession.onOldDeviceUnavailable = { [weak self] in
            self?.pause()
        }
    }

    private func syncNowPlayingPlayback(rate: Float) {
        nowPlaying.updatePlayback(duration: duration, elapsed: currentTime, rate: rate)
    }
}
