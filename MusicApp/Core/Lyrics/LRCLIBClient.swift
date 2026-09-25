import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A record from https://lrclib.net (free, open lyrics database).
struct LRCLIBRecord: Decodable, Hashable, Sendable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?

    var isInstrumental: Bool { instrumental ?? false }
    var hasSynced: Bool { syncedLyrics.nonEmpty != nil }

    /// Parsed lyrics, preferring synced ones. nil for instrumentals or empty records.
    var document: LyricsDocument? {
        if let synced = syncedLyrics.nonEmpty {
            let doc = LRCParser.parse(synced)
            if !doc.isEmpty { return doc }
        }
        if let plain = plainLyrics.nonEmpty {
            let doc = LRCParser.plain(plain)
            if !doc.isEmpty { return doc }
        }
        return nil
    }
}

struct LRCLIBClient: Sendable {
    static let baseURL = "https://lrclib.net/api"

    let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }

    /// Exact lookup first; on a miss, a fuzzy search with a cleaned title, then best-match ranking.
    func fetch(title: String, artist: String, album: String?, duration: TimeInterval?) async throws -> LRCLIBRecord? {
        do {
            let request = Self.makeGetRequest(title: title, artist: artist, album: album, duration: duration)
            let record = try await http.decode(LRCLIBRecord.self, for: request)
            if record.isInstrumental || record.document != nil { return record }
        } catch MusicSourceError.notFound {
            // Fall through to search.
        }

        let search = Self.makeSearchRequest(title: Self.cleanedTitle(title), artist: artist)
        let records = try await http.decode([LRCLIBRecord].self, for: search)
        return Self.bestMatch(records, title: title, artist: artist, duration: duration)
    }

    static func makeGetRequest(title: String, artist: String, album: String?, duration: TimeInterval?) -> URLRequest {
        RequestBuilder.get("\(baseURL)/get", [
            ("track_name", title),
            ("artist_name", artist),
            ("album_name", album.nonEmpty),
            ("duration", duration.flatMap { $0 > 0 ? String(Int($0.rounded())) : nil }),
        ])
    }

    static func makeSearchRequest(title: String, artist: String) -> URLRequest {
        RequestBuilder.get("\(baseURL)/search", [
            ("track_name", title),
            ("artist_name", artist.nonEmpty),
        ])
    }

    /// Picks the most plausible record. Requires at least a partial title match.
    static func bestMatch(_ records: [LRCLIBRecord], title: String, artist: String, duration: TimeInterval?) -> LRCLIBRecord? {
        let wantedTitle = normalize(cleanedTitle(title))
        let wantedArtist = normalize(artist)
        var best: (record: LRCLIBRecord, score: Int)?

        for record in records {
            guard record.isInstrumental || record.document != nil else { continue }
            let recordTitle = normalize(cleanedTitle(record.trackName ?? ""))
            let recordArtist = normalize(record.artistName ?? "")
            var score = 0

            if !wantedTitle.isEmpty, recordTitle == wantedTitle {
                score += 4
            } else if !wantedTitle.isEmpty, !recordTitle.isEmpty,
                      recordTitle.contains(wantedTitle) || wantedTitle.contains(recordTitle) {
                score += 1
            } else {
                continue
            }

            if !wantedArtist.isEmpty, !recordArtist.isEmpty {
                if recordArtist == wantedArtist {
                    score += 3
                } else if recordArtist.contains(wantedArtist) || wantedArtist.contains(recordArtist) {
                    score += 1
                }
            }

            if let duration, duration > 0, let recordDuration = record.duration {
                let delta = abs(recordDuration - duration)
                if delta <= 3 { score += 2 } else if delta <= 10 { score += 1 } else if delta > 30 { score -= 2 }
            }

            if record.hasSynced { score += 2 }

            if best == nil || score > best!.score {
                best = (record, score)
            }
        }
        guard let best, best.score >= 3 else { return nil }
        return best.record
    }

    /// Strips decorations that rarely appear in lyrics databases:
    /// "(Live)", "(feat. X)", "[Explicit]", "（伴奏）", " - Remastered 2011".
    static func cleanedTitle(_ title: String) -> String {
        var result = ""
        var depth = 0
        for character in title {
            switch character {
            case "(", "[", "（", "【", "［":
                depth += 1
            case ")", "]", "）", "】", "］":
                depth = max(0, depth - 1)
            default:
                if depth == 0 { result.append(character) }
            }
        }
        if let dash = result.range(of: " - ") {
            let suffix = result[dash.upperBound...].lowercased()
            let decorations = ["remaster", "live", "version", "edit", "mix", "mono", "stereo", "acoustic", "版"]
            if decorations.contains(where: { suffix.contains($0) }) {
                result = String(result[..<dash.lowerBound])
            }
        }
        let cleaned = result.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }

    /// Case-folded, punctuation/whitespace removed, Traditional Chinese folded to Simplified (on Apple platforms).
    static func normalize(_ string: String) -> String {
        var value = string.lowercased()
        #if canImport(Darwin)
        value = value.applyingTransform(StringTransform(rawValue: "Hant-Hans"), reverse: false) ?? value
        #endif
        return String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
