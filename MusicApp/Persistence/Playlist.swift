import Foundation
import SwiftData

@Model
final class Playlist {
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    init(name: String) {
        self.name = name
        createdAt = Date()
        updatedAt = Date()
    }

    /// SwiftData relationship arrays are unordered; `PlaylistEntry.order` defines the order.
    var orderedEntries: [PlaylistEntry] {
        entries.sorted { $0.order < $1.order }
    }

    var tracks: [Track] {
        orderedEntries.compactMap(\.track)
    }

    var playableTracks: [PlayableTrack] {
        tracks.map(\.playable)
    }

    /// Artwork of the first track that has one, for the playlist cover.
    var coverTrack: PlayableTrack? {
        tracks.first { $0.artworkURLString != nil || $0.localArtworkFilename != nil }?.playable
    }
}
