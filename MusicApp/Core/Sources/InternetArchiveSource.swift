import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Internet Archive audio: public-domain and CC-licensed recordings (netlabels, 78rpm, live concerts...).
///
/// Search returns items (usually albums) as collections; their tracks are fetched lazily from
/// `/metadata/{identifier}` when the user opens one, to avoid N+1 requests per search.
struct InternetArchiveSource: MusicSource {
    static let pageSize = 20
    static let maxTracksPerItem = 300
    static let collectionFilter =
        "mediatype:audio AND collection:(netlabels OR audio_music OR 78rpm OR opensource_audio OR etree) "
        + "AND -collection:(podcasts OR librivoxaudio OR oldtimeradio)"

    /// Lower is better. Other `.mp3` / `.m4a` files are accepted with a worse priority.
    static let formatPriority: [String: Int] = [
        "VBR MP3": 0,
        "320Kbps MP3": 1,
        "256Kbps MP3": 2,
        "192Kbps MP3": 3,
        "128Kbps MP3": 4,
        "MP3": 5,
        "64Kbps MP3": 6,
    ]

    let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }

    var id: SourceID { .internetArchive }

    var capabilities: SourceCapabilities {
        SourceCapabilities(supportedScopes: Set(SearchScope.allCases), pageSize: Self.pageSize, requiresAPIKey: false)
    }

    // MARK: - Search

    func search(_ query: SearchQuery, page: Int) async throws -> SearchPage {
        let text = Self.sanitizeLucene(query.trimmedText)
        guard !text.isEmpty else { return .empty }
        let request = Self.makeSearchRequest(query: query, page: page)
        let response = try await http.decode(IASearchResponse.self, for: request)
        let body = response.response
        let start = body.start ?? (max(page, 1) - 1) * Self.pageSize
        return SearchPage(
            items: Self.map(body.docs).map { .collection($0) },
            page: page,
            hasMore: start + body.docs.count < body.numFound,
            totalCount: body.numFound
        )
    }

    static func makeQueryString(_ query: SearchQuery) -> String {
        let text = sanitizeLucene(query.trimmedText)
        let clause: String
        switch query.scope {
        case .all: clause = "(\(text))"
        case .song, .album: clause = "title:(\(text))"
        case .artist: clause = "creator:(\(text))"
        }
        return "\(clause) AND \(collectionFilter)"
    }

    static func makeSearchRequest(query: SearchQuery, page: Int) -> URLRequest {
        RequestBuilder.get("https://archive.org/advancedsearch.php", [
            ("q", makeQueryString(query)),
            ("fl[]", "identifier"),
            ("fl[]", "title"),
            ("fl[]", "creator"),
            ("fl[]", "licenseurl"),
            ("fl[]", "year"),
            ("rows", String(pageSize)),
            ("page", String(max(page, 1))),
            ("output", "json"),
        ])
    }

    /// Replaces Lucene special characters with spaces (safer than escaping through URL encoding).
    static func sanitizeLucene(_ text: String) -> String {
        let special = Set("+-&|!(){}[]^\"~*?:\\/")
        let replaced = String(text.map { special.contains($0) ? " " : $0 })
        return replaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    static func map(_ docs: [IADoc]) -> [RemoteCollection] {
        docs.map { doc in
            RemoteCollection(
                id: "ia:\(doc.identifier)",
                source: .internetArchive,
                title: doc.title?.first ?? doc.identifier,
                subtitle: doc.creator?.joined,
                artworkURL: thumbnailURL(doc.identifier),
                license: LicenseInfo.fromURL(doc.licenseurl?.first),
                webPageURL: URL(string: "https://archive.org/details/\(doc.identifier)"),
                year: doc.year?.value.nonEmpty
            )
        }
    }

    static func thumbnailURL(_ identifier: String) -> URL? {
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        return URL(string: "https://archive.org/services/img/\(encoded)")
    }

    // MARK: - Item expansion

    func tracks(in collection: RemoteCollection) async throws -> [PlayableTrack] {
        let identifier = Self.identifier(from: collection.id)
        let request = Self.makeMetadataRequest(identifier: identifier)
        let response = try await http.decode(IAMetadataResponse.self, for: request)
        return Self.tracks(from: response, identifier: identifier, fallback: collection)
    }

    static func identifier(from collectionID: String) -> String {
        collectionID.hasPrefix("ia:") ? String(collectionID.dropFirst(3)) : collectionID
    }

    static func makeMetadataRequest(identifier: String) -> URLRequest {
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        return RequestBuilder.get("https://archive.org/metadata/\(encoded)", [])
    }

    static func priority(of file: IAFile) -> Int? {
        if let format = file.format, let priority = formatPriority[format] { return priority }
        let lower = file.name.lowercased()
        if lower.hasSuffix(".mp3") { return 10 }
        if lower.hasSuffix(".m4a") { return 11 }
        return nil
    }

    /// Picks one playable file per original recording (derivatives point back via `original`).
    static func selectFiles(_ files: [IAFile]) -> [IAFile] {
        var best: [String: (file: IAFile, priority: Int)] = [:]
        var groupOrder: [String] = []
        for file in files {
            guard let priority = priority(of: file) else { continue }
            let group = file.source == "original" ? file.name : (file.original ?? file.name)
            if let existing = best[group] {
                if priority < existing.priority { best[group] = (file, priority) }
            } else {
                best[group] = (file, priority)
                groupOrder.append(group)
            }
        }
        let byName = Dictionary(files.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let selected = groupOrder.compactMap { group -> IAFile? in
            guard let file = best[group]?.file else { return nil }
            // A derivative (e.g. the MP3 of a FLAC original) usually lacks tags; inherit them.
            guard file.name != group, let original = byName[group] else { return file }
            return file.inheriting(from: original)
        }
        return Array(selected.sorted(by: trackOrder).prefix(maxTracksPerItem))
    }

    /// Leading integer of "01", "3/12", "Track 4"... used for sorting.
    static func trackNumber(_ file: IAFile) -> Int? {
        guard let raw = file.track?.value else { return nil }
        let digits = raw.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
        return Int(digits)
    }

    static func trackOrder(_ lhs: IAFile, _ rhs: IAFile) -> Bool {
        switch (trackNumber(lhs), trackNumber(rhs)) {
        case let (l?, r?) where l != r:
            return l < r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.name.compare(rhs.name, options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
    }

    static func tracks(from response: IAMetadataResponse, identifier: String, fallback: RemoteCollection?) -> [PlayableTrack] {
        let metadata = response.metadata
        let itemTitle = metadata?.title?.first ?? fallback?.title
        let itemCreator = metadata?.creator?.joined ?? fallback?.subtitle
        let license = LicenseInfo.fromURL(metadata?.licenseurl?.first) ?? fallback?.license
        let artwork = thumbnailURL(identifier)
        let page = URL(string: "https://archive.org/details/\(identifier)")

        return selectFiles(response.files).map { file in
            let url = FileNaming.iaDownloadURL(identifier: identifier, filename: file.name)
            let baseName = file.name.split(separator: "/").last.map(String.init) ?? file.name
            let nameWithoutExtension = baseName.lastIndex(of: ".").map { String(baseName[..<$0]) } ?? baseName
            return PlayableTrack(
                id: "ia:\(identifier)/\(file.name)",
                source: .internetArchive,
                title: file.title?.first ?? nameWithoutExtension,
                artist: file.artist?.first ?? file.creator?.first ?? itemCreator ?? "未知艺术家",
                album: file.album?.first ?? itemTitle,
                duration: DurationParser.seconds(file.length?.value),
                artworkURL: artwork,
                streamURL: url,
                downloadURL: url,
                isPreview: false,
                license: license,
                webPageURL: page,
                releaseDate: metadata?.date?.first
            )
        }
    }
}
