import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Openverse audio search: openly licensed (CC) full tracks. No key required.
///
/// Notes (verified): anonymous limit is 20 requests/minute and 200/day; `page_size` must be <= 20
/// and results cannot go deeper than 240 (401 beyond); `q` silently overrides `title`/`creator`;
/// Wikimedia results are Ogg, which AVPlayer cannot play; `category=music` returns Jamendo MP3s.
struct OpenverseSource: MusicSource {
    static let pageSize = 20
    static let maxDepth = 240
    static let playableFiletypes: Set<String> = ["mp3", "mp32", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "mp4"]

    let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }

    var id: SourceID { .openverse }

    var capabilities: SourceCapabilities {
        SourceCapabilities(supportedScopes: [.all, .song, .artist], pageSize: Self.pageSize, requiresAPIKey: false)
    }

    func search(_ query: SearchQuery, page: Int) async throws -> SearchPage {
        guard !query.trimmedText.isEmpty else { return .empty }
        guard (page - 1) * Self.pageSize < Self.maxDepth else {
            return SearchPage(items: [], page: page, hasMore: false, totalCount: nil)
        }
        let request = Self.makeSearchRequest(query: query, page: page)
        let response: OpenverseSearchResponse
        do {
            response = try await http.decode(OpenverseSearchResponse.self, for: request)
        } catch MusicSourceError.http(401) where page > 1 {
            // Pagination depth exceeded.
            return SearchPage(items: [], page: page, hasMore: false, totalCount: nil)
        }
        let pageCount = response.page_count ?? 0
        return SearchPage(
            items: Self.map(response.results).map { .track($0) },
            page: page,
            hasMore: page < pageCount && page * Self.pageSize < Self.maxDepth,
            totalCount: response.result_count
        )
    }

    static func makeSearchRequest(query: SearchQuery, page: Int) -> URLRequest {
        let text = query.trimmedText
        var items: [(String, String?)] = []
        switch query.scope {
        case .song: items.append(("title", text))
        case .artist: items.append(("creator", text))
        case .all, .album: items.append(("q", text))
        }
        items.append(("page", String(max(page, 1))))
        items.append(("page_size", String(pageSize)))
        if !query.includeNonMusic {
            items.append(("category", "music"))
        }
        return RequestBuilder.get("https://api.openverse.org/v1/audio/", items)
    }

    static func isPlayable(_ dto: OpenverseAudioDTO) -> Bool {
        if let filetype = dto.filetype?.lowercased() {
            return playableFiletypes.contains(filetype)
        }
        guard let url = dto.url.flatMap(URL.init(string:)) else { return false }
        return FileNaming.playableExtensions.contains(url.pathExtension.lowercased())
    }

    static func map(_ results: [OpenverseAudioDTO]) -> [PlayableTrack] {
        results.compactMap { dto in
            guard isPlayable(dto), let url = dto.url.nonEmpty.flatMap(URL.init(string:)) else { return nil }
            let license = dto.license.nonEmpty.map {
                LicenseInfo(code: $0, version: dto.license_version, url: dto.license_url.flatMap(URL.init(string:)))
            }
            return PlayableTrack(
                id: "openverse:\(dto.id)",
                source: .openverse,
                title: dto.title.nonEmpty ?? "未命名",
                artist: dto.creator.nonEmpty ?? "未知艺术家",
                album: dto.audio_set?.title.nonEmpty,
                duration: dto.duration.flatMap { $0 > 0 ? $0 / 1000 : nil },
                artworkURL: dto.thumbnail.nonEmpty.flatMap(URL.init(string:)),
                streamURL: url,
                downloadURL: url,
                isPreview: false,
                license: license,
                attribution: dto.attribution.nonEmpty,
                webPageURL: dto.foreign_landing_url.nonEmpty.flatMap(URL.init(string:)),
                genre: dto.genres?.first
            )
        }
    }
}
