import Foundation
import Observation

/// A set of tracks waiting for the playlist picker.
struct TrackSelection: Identifiable {
    let id = UUID()
    let tracks: [PlayableTrack]
}

/// Common actions on tracks, shared by every list so views stay small.
@MainActor
@Observable
final class TrackActions {
    /// Drives the "add to playlist" sheet.
    var playlistPicker: TrackSelection?
    /// Drives the track info sheet.
    var infoTrack: PlayableTrack?
    /// Short message shown at the top of the screen.
    private(set) var toast: String?
    /// While Now Playing is up, sheets are presented from it instead of the root.
    var isNowPlayingPresented = false

    let library: LibraryStore
    let player: PlayerManager
    let downloads: DownloadManager
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(library: LibraryStore, player: PlayerManager, downloads: DownloadManager) {
        self.library = library
        self.player = player
        self.downloads = downloads
    }

    /// Plays `track`, queueing the rest of `list` around it.
    func play(_ track: PlayableTrack, in list: [PlayableTrack]) {
        if let index = list.firstIndex(where: { $0.id == track.id }) {
            player.play(list, startAt: index)
        } else {
            player.play([track])
        }
    }

    func playAll(_ tracks: [PlayableTrack], shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        player.play(tracks, startAt: shuffle ? Int.random(in: 0..<tracks.count) : 0, shuffle: shuffle)
    }

    func playNext(_ tracks: [PlayableTrack]) {
        player.playNext(tracks)
        showToast(tracks.count == 1 ? "将在下一首播放" : "\(tracks.count) 首歌将在下一首播放")
    }

    func addToQueue(_ tracks: [PlayableTrack]) {
        player.addToQueue(tracks)
        showToast(tracks.count == 1 ? "已加入播放队列" : "已将 \(tracks.count) 首歌加入播放队列")
    }

    func isFavorite(_ track: PlayableTrack) -> Bool {
        _ = library.revision
        return library.isFavorite(track.id)
    }

    func toggleFavorite(_ track: PlayableTrack) {
        library.toggleFavorite(track)
        showToast(library.isFavorite(track.id) ? "已收藏" : "已取消收藏")
    }

    func addToLibrary(_ track: PlayableTrack) {
        library.upsert(track)
        showToast("已加入曲库")
    }

    func isInLibrary(_ track: PlayableTrack) -> Bool {
        _ = library.revision
        return library.contains(track.id)
    }

    func addToPlaylist(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        playlistPicker = TrackSelection(tracks: tracks)
    }

    func download(_ track: PlayableTrack) {
        guard downloads.canDownload(track) else {
            showToast(track.isPreview ? "试听片段不支持下载" : "该曲目不允许下载")
            return
        }
        downloads.download(track)
        showToast("开始下载")
    }

    func download(_ tracks: [PlayableTrack]) {
        let allowed = tracks.filter { downloads.canDownload($0) }
        downloads.download(allowed)
        showToast(allowed.isEmpty ? "没有可下载的曲目" : "开始下载 \(allowed.count) 首")
    }

    func removeDownload(_ track: PlayableTrack) {
        downloads.removeDownload(track)
        showToast("已删除下载")
    }

    func delete(_ track: Track) {
        let id = track.stableID
        library.deleteTrack(track)
        player.removeTrackEverywhere(id)
    }

    func showInfo(_ track: PlayableTrack) {
        infoTrack = track
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
