import Foundation

/// The value type that flows between search, the play queue, Now Playing and downloads.
/// Persisted library items (`Track`) convert to and from this type.
struct PlayableTrack: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier: "itunes:<trackId>", "openverse:<uuid>", "ia:<identifier>/<file>",
    /// "jamendo:<id>" or "local:<uuid>".
    var id: String
    var source: SourceID
    var title: String
    var artist: String
    var album: String?
    /// Length of the full song from metadata (used for lyrics lookup).
    /// For iTunes previews this is the full song length, not 30 seconds.
    var duration: TimeInterval?
    var artworkURL: URL?
    /// File name inside Application Support/Artwork.
    var localArtworkFilename: String?
    var streamURL: URL?
    /// File name inside Documents/Music. Never an absolute path: the container path changes between installs.
    var localFilename: String?
    /// nil when the track may not be downloaded.
    var downloadURL: URL?
    var isPreview: Bool
    var license: LicenseInfo?
    var attribution: String?
    var webPageURL: URL?
    var genre: String?
    var releaseDate: String?

    init(
        id: String,
        source: SourceID,
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil,
        localArtworkFilename: String? = nil,
        streamURL: URL? = nil,
        localFilename: String? = nil,
        downloadURL: URL? = nil,
        isPreview: Bool = false,
        license: LicenseInfo? = nil,
        attribution: String? = nil,
        webPageURL: URL? = nil,
        genre: String? = nil,
        releaseDate: String? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.localArtworkFilename = localArtworkFilename
        self.streamURL = streamURL
        self.localFilename = localFilename
        self.downloadURL = downloadURL
        self.isPreview = isPreview
        self.license = license
        self.attribution = attribution
        self.webPageURL = webPageURL
        self.genre = genre
        self.releaseDate = releaseDate
    }

    var isDownloadable: Bool { downloadURL != nil && source.supportsDownload }

    /// "Artist · Album" for list subtitles.
    var subtitle: String {
        if let album, !album.isEmpty, album != title { return "\(artist) · \(album)" }
        return artist
    }

    /// Text required by CC BY licenses when no explicit attribution string is provided.
    var attributionText: String {
        if let attribution, !attribution.isEmpty { return attribution }
        var text = "\"\(title)\" by \(artist)"
        if let license { text += " (\(license.displayName))" }
        return text
    }
}
