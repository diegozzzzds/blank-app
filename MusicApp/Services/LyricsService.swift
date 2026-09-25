import Foundation
import Observation

/// Loads lyrics for the current track: user-imported .lrc first, then the offline cache, then LRCLIB.
@MainActor
@Observable
final class LyricsService {
    enum Origin: Equatable {
        case custom
        case cache
        case lrclib
    }

    enum State: Equatable {
        case idle
        case loading
        case loaded(LyricsDocument, Origin)
        case instrumental
        case notFound
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var trackID: String?

    private let client: LRCLIBClient
    private let library: LibraryStore
    @ObservationIgnored private var memoryCache: [String: State] = [:]

    init(client: LRCLIBClient, library: LibraryStore) {
        self.client = client
        self.library = library
    }

    func load(for track: PlayableTrack?, force: Bool = false) async {
        guard let track else {
            trackID = nil
            state = .idle
            return
        }
        if !force, trackID == track.id, state != .idle, !isFailed {
            return
        }
        trackID = track.id

        if let stored = library.track(withID: track.id) {
            if let custom = stored.customLyrics.nonEmpty {
                state = .loaded(adjusted(LRCParser.parse(custom), for: track), .custom)
                return
            }
            if !force, let cached = stored.cachedLyrics.nonEmpty {
                let doc = stored.cachedLyricsSynced ? LRCParser.parse(cached) : LRCParser.plain(cached)
                state = .loaded(adjusted(doc, for: track), .cache)
                return
            }
        }
        if !force, let cached = memoryCache[track.id] {
            state = cached
            return
        }

        state = .loading
        do {
            let record = try await client.fetch(
                title: track.title,
                artist: track.artist == "未知艺术家" ? "" : track.artist,
                album: track.album,
                duration: track.duration
            )
            guard trackID == track.id else { return }
            let result: State
            if let record, record.isInstrumental {
                result = .instrumental
            } else if let record, let doc = record.document {
                result = .loaded(adjusted(doc, for: track), .lrclib)
                // Keep a copy for offline use when the track is in the library.
                library.setCachedLyrics(doc.serialized(), synced: doc.isSynced, for: track.id)
            } else {
                result = .notFound
            }
            memoryCache[track.id] = result
            state = result
        } catch {
            guard trackID == track.id else { return }
            let wrapped = MusicSourceError.wrap(error)
            if wrapped == .cancelled { return }
            if wrapped == .notFound {
                memoryCache[track.id] = .notFound
                state = .notFound
            } else {
                state = .failed(wrapped.errorDescription ?? "加载歌词失败")
            }
        }
    }

    func clearMemoryCache() {
        memoryCache.removeAll()
        if case .loaded(_, .lrclib) = state {
            trackID = nil
            state = .idle
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// Previews are a 30-second excerpt from the middle of the song, so timestamps can't line up.
    private func adjusted(_ doc: LyricsDocument, for track: PlayableTrack) -> LyricsDocument {
        track.isPreview ? doc.unsynced() : doc
    }
}
