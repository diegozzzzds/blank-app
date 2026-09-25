import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Jamendo: Creative Commons independent music, full-length streams. Requires a free client_id
/// from https://devportal.jamendo.com that the user enters in Settings.
struct JamendoSource: MusicSource {
    static let pageSize = 20

    let http: HTTPClient
    let clientID: String

    init(http: HTTPClient, clientID: String) {
        self.http = http
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var id: SourceID { .jamendo }

    var capabilities: SourceCapabilities {
        SourceCapabilities(supportedScopes: Set(SearchScope.allCases), pageSize: Self.pageSize, requiresAPIKey: true)
    }

    func search(_ query: SearchQuery, page: Int) async throws -> SearchPage {
        guard !clientID.isEmpty else { throw MusicSourceError.missingAPIKey }
        guard !query.trimmedText.isEmpty else { return .empty }
        let request = Self.makeSearchRequest(query: query, page: page, clientID: clientID)
        let response = try await http.decode(JamendoResponse.self, for: request)
        try Self.check(response.headers)
        let offset = (max(page, 1) - 1) * Self.pageSize
        let total = response.headers.results_fullcount
        let hasMore: Bool
        if let total {
            hasMore = offset + response.results.count < total
        } else {
            hasMore = response.results.count == Self.pageSize
        }
        return SearchPage(
            items: Self.map(response.results).map { .track($0) },
            page: page,
            hasMore: hasMore,
            totalCount: total
        )
    }

    /// Fetches one track to confirm the client_id works (used by Settings).
    func testConnection() async throws {
        let request = RequestBuilder.get("https://api.jamendo.com/v3.0/tracks/", [
            ("client_id", clientID),
            ("format", "json"),
            ("limit", "1"),
        ])
        let response = try await http.decode(JamendoResponse.self, for: request)
        try Self.check(response.headers)
    }

    static func check(_ headers: JamendoResponse.Headers) throws {
        if headers.status == "failed" || (headers.code ?? 0) != 0 {
            if headers.code == 5 { throw MusicSourceError.api("client_id 无效") }
            throw MusicSourceError.api(headers.error_message.nonEmpty ?? "未知错误（\(headers.code ?? -1)）")
        }
    }

    static func makeSearchRequest(query: SearchQuery, page: Int, clientID: String) -> URLRequest {
        let text = query.trimmedText
        let searchKey: String
        switch query.scope {
        case .all: searchKey = "search"
        case .song: searchKey = "namesearch"
        case .artist: searchKey = "artist_name"
        case .album: searchKey = "album_name"
        }
        return RequestBuilder.get("https://api.jamendo.com/v3.0/tracks/", [
            ("client_id", clientID),
            ("format", "json"),
            ("limit", String(pageSize)),
            ("offset", String((max(page, 1) - 1) * pageSize)),
            (searchKey, text),
            ("audioformat", "mp32"),
            ("imagesize", "300"),
            ("include", "musicinfo licenses"),
            ("fullcount", "true"),
        ])
    }

    static func map(_ results: [JamendoTrackDTO]) -> [PlayableTrack] {
        results.compactMap { dto in
            guard let stream = dto.audio.nonEmpty.flatMap(URL.init(string:)) else { return nil }
            let artwork = (dto.image.nonEmpty ?? dto.album_image.nonEmpty).flatMap(URL.init(string:))
            let download = dto.audiodownload_allowed == true
                ? dto.audiodownload.nonEmpty.flatMap(URL.init(string:))
                : nil
            return PlayableTrack(
                id: "jamendo:\(dto.id.value)",
                source: .jamendo,
                title: dto.name.nonEmpty ?? "未命名",
                artist: dto.artist_name.nonEmpty ?? "未知艺术家",
                album: dto.album_name.nonEmpty,
                duration: dto.duration.flatMap { TimeInterval($0.value) },
                artworkURL: artwork,
                streamURL: stream,
                downloadURL: download,
                isPreview: false,
                license: LicenseInfo.fromURL(dto.license_ccurl),
                webPageURL: dto.shareurl.nonEmpty.flatMap(URL.init(string:)),
                genre: dto.musicinfo?.tags?.genres?.first,
                releaseDate: dto.releasedate.nonEmpty
            )
        }
    }
}
