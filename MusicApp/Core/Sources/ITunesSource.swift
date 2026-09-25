import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// iTunes Search API: mainstream catalog, artwork and 30-second previews. No key required.
///
/// Notes (verified): `country=CN` returns nothing; `offset` is ignored, so we fetch up to 200 results
/// once and page client-side; rate-limited requests return HTTP 403.
struct ITunesSource: MusicSource {
    static let pageSize = 25
    static let fetchLimit = 200
    static let supportedCountries = ["HK", "TW", "US", "JP", "SG", "GB"]

    let http: HTTPClient
    let country: String
    private let cache: ResultCache<String, [PlayableTrack]>

    init(http: HTTPClient, country: String = "HK", cache: ResultCache<String, [PlayableTrack]> = ResultCache()) {
        self.http = http
        self.country = country.uppercased() == "CN" ? "HK" : country.uppercased()
        self.cache = cache
    }

    var id: SourceID { .itunes }

    var capabilities: SourceCapabilities {
        SourceCapabilities(supportedScopes: Set(SearchScope.allCases), pageSize: Self.pageSize, requiresAPIKey: false)
    }

    func search(_ query: SearchQuery, page: Int) async throws -> SearchPage {
        let text = query.trimmedText
        guard !text.isEmpty else { return .empty }
        let key = "\(country)|\(query.scope.rawValue)|\(text.lowercased())"

        let tracks: [PlayableTrack]
        if let cached = await cache.value(for: key) {
            tracks = cached
        } else {
            let request = Self.makeSearchRequest(query: query, country: country)
            let response: ITunesSearchResponse
            do {
                response = try await http.decode(ITunesSearchResponse.self, for: request)
            } catch MusicSourceError.http(403) {
                throw MusicSourceError.rateLimited(retryAfter: 60)
            }
            tracks = Self.map(response.results)
            await cache.set(tracks, for: key)
        }

        let start = (max(page, 1) - 1) * Self.pageSize
        guard start < tracks.count else {
            return SearchPage(items: [], page: page, hasMore: false, totalCount: tracks.count)
        }
        let end = min(start + Self.pageSize, tracks.count)
        return SearchPage(
            items: tracks[start..<end].map { .track($0) },
            page: page,
            hasMore: end < tracks.count,
            totalCount: tracks.count
        )
    }

    static func makeSearchRequest(query: SearchQuery, country: String) -> URLRequest {
        let attribute: String?
        switch query.scope {
        case .all: attribute = nil
        case .song: attribute = "songTerm"
        case .artist: attribute = "artistTerm"
        case .album: attribute = "albumTerm"
        }
        return RequestBuilder.get("https://itunes.apple.com/search", [
            ("term", query.trimmedText),
            ("media", "music"),
            ("entity", "song"),
            ("attribute", attribute),
            ("limit", String(fetchLimit)),
            ("country", country),
        ])
    }

    static func map(_ results: [ITunesTrackDTO]) -> [PlayableTrack] {
        var seen = Set<Int>()
        return results.compactMap { dto in
            guard dto.kind == nil || dto.kind == "song",
                  let trackId = dto.trackId,
                  let preview = dto.previewUrl.nonEmpty.flatMap(URL.init(string:)),
                  seen.insert(trackId).inserted else { return nil }
            return PlayableTrack(
                id: "itunes:\(trackId)",
                source: .itunes,
                title: dto.trackName.nonEmpty ?? "未知歌曲",
                artist: dto.artistName.nonEmpty ?? "未知艺术家",
                album: dto.collectionName.nonEmpty,
                duration: dto.trackTimeMillis.map { TimeInterval($0) / 1000 },
                artworkURL: dto.artworkUrl100.nonEmpty.flatMap(URL.init(string:)).map { ArtworkURL.itunes($0, size: 600) },
                streamURL: preview,
                downloadURL: nil,
                isPreview: true,
                webPageURL: dto.trackViewUrl.nonEmpty.flatMap(URL.init(string:)),
                genre: dto.primaryGenreName.nonEmpty,
                releaseDate: dto.releaseDate.nonEmpty
            )
        }
    }
}
