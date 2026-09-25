import Foundation

enum SearchScope: String, CaseIterable, Hashable, Codable, Sendable {
    case all
    case song
    case artist
    case album

    var title: String {
        switch self {
        case .all: return "全部"
        case .song: return "歌曲"
        case .artist: return "歌手"
        case .album: return "专辑"
        }
    }
}

struct SearchQuery: Hashable, Sendable {
    var text: String
    var scope: SearchScope
    /// Openverse only: include sound effects and other non-music audio.
    var includeNonMusic: Bool

    init(text: String, scope: SearchScope = .all, includeNonMusic: Bool = false) {
        self.text = text
        self.scope = scope
        self.includeNonMusic = includeNonMusic
    }

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when the query contains CJK characters (some sources are English-centric).
    var containsCJK: Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }
}

/// A group of tracks that is expanded lazily (an Internet Archive item, typically an album).
struct RemoteCollection: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var source: SourceID
    var title: String
    var subtitle: String?
    var artworkURL: URL?
    var license: LicenseInfo?
    var webPageURL: URL?
    var year: String?
}

enum SearchResultItem: Identifiable, Hashable, Sendable {
    case track(PlayableTrack)
    case collection(RemoteCollection)

    var id: String {
        switch self {
        case .track(let track): return track.id
        case .collection(let collection): return collection.id
        }
    }

    var track: PlayableTrack? {
        if case .track(let track) = self { return track }
        return nil
    }
}

struct SearchPage: Hashable, Sendable {
    var items: [SearchResultItem]
    /// 1-based page number.
    var page: Int
    var hasMore: Bool
    var totalCount: Int?

    static let empty = SearchPage(items: [], page: 1, hasMore: false, totalCount: 0)
}
