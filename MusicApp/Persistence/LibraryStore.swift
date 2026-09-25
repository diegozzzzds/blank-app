import Foundation
import Observation
import SwiftData

/// All writes to the library go through here so every mutation is saved and IDs stay unique.
@MainActor
@Observable
final class LibraryStore {
    let context: ModelContext
    private let files: FileLocations

    /// Bumped on every change so views that cache derived state can refresh.
    private(set) var revision = 0

    init(context: ModelContext, files: FileLocations) {
        self.context = context
        self.files = files
    }

    // MARK: - Tracks

    func track(withID id: String) -> Track? {
        var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.stableID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func contains(_ id: String) -> Bool {
        track(withID: id) != nil
    }

    /// Returns the stored track for `playable`, inserting it if needed.
    /// Inserting a duplicate `.unique` value would overwrite the row, so always fetch first.
    @discardableResult
    func upsert(_ playable: PlayableTrack) -> Track {
        if let existing = track(withID: playable.id) {
            existing.merge(from: playable)
            if existing.localFilename == nil, let local = playable.localFilename {
                existing.localFilename = local
            }
            if existing.localArtworkFilename == nil, let artwork = playable.localArtworkFilename {
                existing.localArtworkFilename = artwork
            }
            save()
            return existing
        }
        let track = Track(from: playable)
        context.insert(track)
        save()
        return track
    }

    func isFavorite(_ id: String) -> Bool {
        track(withID: id)?.isFavorite ?? false
    }

    func toggleFavorite(_ playable: PlayableTrack) {
        let track = upsert(playable)
        track.isFavorite.toggle()
        track.favoritedAt = track.isFavorite ? Date() : nil
        save()
    }

    func setFavorite(_ playable: PlayableTrack, _ favorite: Bool) {
        let track = upsert(playable)
        guard track.isFavorite != favorite else { return }
        track.isFavorite = favorite
        track.favoritedAt = favorite ? Date() : nil
        save()
    }

    func setLocalFile(_ filename: String?, for id: String) {
        guard let track = track(withID: id) else { return }
        track.localFilename = filename
        save()
    }

    func setCachedLyrics(_ lyrics: String?, synced: Bool, for id: String) {
        guard let track = track(withID: id) else { return }
        track.cachedLyrics = lyrics
        track.cachedLyricsSynced = synced
        save()
    }

    func setCustomLyrics(_ lyrics: String?, for id: String) {
        guard let track = track(withID: id) else { return }
        track.customLyrics = lyrics
        save()
    }

    func markPlayed(_ id: String) {
        guard let track = track(withID: id) else { return }
        track.playCount += 1
        track.lastPlayedAt = Date()
        save()
    }

    /// Deletes the track, its playlist entries (cascade) and any local audio/artwork files.
    func deleteTrack(_ track: Track) {
        if let filename = track.localFilename {
            try? FileManager.default.removeItem(at: files.musicURL(filename))
        }
        if let artwork = track.localArtworkFilename {
            try? FileManager.default.removeItem(at: files.artworkURL(artwork))
        }
        for entry in track.playlistEntries {
            entry.playlist?.entries.removeAll { $0.persistentModelID == entry.persistentModelID }
            entry.playlist?.updatedAt = Date()
        }
        context.delete(track)
        save()
    }

    /// Removes a downloaded file but keeps the track (it will stream again).
    func removeDownload(for id: String) {
        guard let track = track(withID: id), let filename = track.localFilename else { return }
        if track.source == .local {
            deleteTrack(track)
            return
        }
        try? FileManager.default.removeItem(at: files.musicURL(filename))
        track.localFilename = nil
        save()
    }

    /// Case- and diacritic-insensitive search over title, artist and album.
    func searchLibrary(_ text: String, limit: Int = 50) -> [Track] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var descriptor = FetchDescriptor<Track>(
            predicate: #Predicate { track in
                track.title.localizedStandardContains(term)
                    || track.artist.localizedStandardContains(term)
                    || (track.album ?? "").localizedStandardContains(term)
            },
            sortBy: [SortDescriptor(\.title)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func allDownloadedTracks() -> [Track] {
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.localFilename != nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let playlist = Playlist(name: trimmed.isEmpty ? "新建歌单" : trimmed)
        context.insert(playlist)
        save()
        return playlist
    }

    func rename(_ playlist: Playlist, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlist.name = trimmed
        playlist.updatedAt = Date()
        save()
    }

    func delete(_ playlist: Playlist) {
        context.delete(playlist)
        save()
    }

    func add(_ tracks: [PlayableTrack], to playlist: Playlist) {
        var next = (playlist.entries.map(\.order).max() ?? -1) + 1
        for playable in tracks {
            let track = upsert(playable)
            let entry = PlaylistEntry(order: next, track: track, playlist: playlist)
            context.insert(entry)
            playlist.entries.append(entry)
            next += 1
        }
        playlist.updatedAt = Date()
        save()
    }

    func removeEntries(at offsets: IndexSet, from playlist: Playlist) {
        let ordered = playlist.orderedEntries
        let doomed = offsets.compactMap { ordered.indices.contains($0) ? ordered[$0] : nil }
        let doomedIDs = Set(doomed.map(\.persistentModelID))
        playlist.entries.removeAll { doomedIDs.contains($0.persistentModelID) }
        for entry in doomed {
            context.delete(entry)
        }
        renumber(playlist)
    }

    func moveEntries(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        var ordered = playlist.orderedEntries
        let moving = source.sorted().compactMap { ordered.indices.contains($0) ? ordered[$0] : nil }
        let adjusted = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where ordered.indices.contains(index) {
            ordered.remove(at: index)
        }
        ordered.insert(contentsOf: moving, at: min(max(adjusted, 0), ordered.count))
        for (index, entry) in ordered.enumerated() {
            entry.order = index
        }
        playlist.updatedAt = Date()
        save()
    }

    private func renumber(_ playlist: Playlist) {
        for (index, entry) in playlist.orderedEntries.enumerated() {
            entry.order = index
        }
        playlist.updatedAt = Date()
        save()
    }

    // MARK: - Saving

    func save() {
        do {
            try context.save()
        } catch {
            print("SwiftData save failed: \(error)")
        }
        revision &+= 1
    }
}
