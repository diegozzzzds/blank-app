import Foundation
import SwiftData

/// Join model between `Playlist` and `Track` that carries the position,
/// so the same song can appear twice and ordering is stable.
@Model
final class PlaylistEntry {
    var order: Int = 0
    var addedAt: Date = Date()
    var playlist: Playlist?
    var track: Track?

    init(order: Int, track: Track, playlist: Playlist) {
        self.order = order
        self.addedAt = Date()
        self.track = track
        self.playlist = playlist
    }
}
