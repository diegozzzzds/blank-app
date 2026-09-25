import Foundation
import SwiftData

/// A track the user kept: favorited, added to a playlist, downloaded or imported.
/// Merely playing a search result never creates one.
@Model
final class Track {
    @Attribute(.unique) var stableID: String = ""
    /// `SourceID.rawValue`. Stored as a String because enums in `#Predicate` are unreliable on iOS 17.
    var sourceRaw: String = SourceID.local.rawValue
    var title: String = ""
    var artist: String = ""
    var album: String?
    var duration: Double?
    var artworkURLString: String?
    var localArtworkFilename: String?
    var streamURLString: String?
    var downloadURLString: String?
    var webPageURLString: String?
    /// Relative to Documents/Music.
    var localFilename: String?
    var isPreview: Bool = false
    var licenseCode: String?
    var licenseVersion: String?
    var licenseURLString: String?
    var attribution: String?
    var genre: String?
    var releaseDate: String?
    var isFavorite: Bool = false
    var favoritedAt: Date?
    var dateAdded: Date = Date()
    var lastPlayedAt: Date?
    var playCount: Int = 0
    /// Lyrics imported by the user (.lrc next to the audio file). Takes precedence over the cache.
    var customLyrics: String?
    /// Lyrics fetched from LRCLIB, cached for offline use.
    var cachedLyrics: String?
    var cachedLyricsSynced: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.track)
    var playlistEntries: [PlaylistEntry] = []

    init(from track: PlayableTrack) {
        stableID = track.id
        dateAdded = Date()
        merge(from: track)
        localFilename = track.localFilename
        localArtworkFilename = track.localArtworkFilename
    }

    var source: SourceID {
        get { SourceID(rawValue: sourceRaw) ?? .local }
        set { sourceRaw = newValue.rawValue }
    }

    var isDownloaded: Bool { localFilename != nil }

    var license: LicenseInfo? {
        guard let licenseCode else { return nil }
        return LicenseInfo(code: licenseCode, version: licenseVersion, url: licenseURLString.flatMap(URL.init(string:)))
    }

    var playable: PlayableTrack {
        PlayableTrack(
            id: stableID,
            source: source,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: artworkURLString.flatMap(URL.init(string:)),
            localArtworkFilename: localArtworkFilename,
            streamURL: streamURLString.flatMap(URL.init(string:)),
            localFilename: localFilename,
            downloadURL: downloadURLString.flatMap(URL.init(string:)),
            isPreview: isPreview,
            license: license,
            attribution: attribution,
            webPageURL: webPageURLString.flatMap(URL.init(string:)),
            genre: genre,
            releaseDate: releaseDate
        )
    }

    /// Updates descriptive metadata only. Never touches favorites, local files or lyrics.
    func merge(from track: PlayableTrack) {
        source = track.source
        title = track.title
        artist = track.artist
        album = track.album
        duration = track.duration ?? duration
        artworkURLString = track.artworkURL?.absoluteString ?? artworkURLString
        streamURLString = track.streamURL?.absoluteString ?? streamURLString
        downloadURLString = track.downloadURL?.absoluteString ?? downloadURLString
        webPageURLString = track.webPageURL?.absoluteString ?? webPageURLString
        isPreview = track.isPreview
        licenseCode = track.license?.code ?? licenseCode
        licenseVersion = track.license?.version ?? licenseVersion
        licenseURLString = track.license?.url?.absoluteString ?? licenseURLString
        attribution = track.attribution ?? attribution
        genre = track.genre ?? genre
        releaseDate = track.releaseDate ?? releaseDate
    }
}
