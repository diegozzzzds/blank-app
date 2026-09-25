import Foundation
@testable import MusicApp

/// A configurable source for aggregator tests.
struct StubSource: MusicSource {
    enum Behavior: Sendable {
        case succeed([PlayableTrack])
        case fail(MusicSourceError)
        case delay(UInt64, [PlayableTrack])
    }

    let id: SourceID
    let behavior: Behavior

    var capabilities: SourceCapabilities {
        SourceCapabilities(supportedScopes: Set(SearchScope.allCases), pageSize: 20, requiresAPIKey: false)
    }

    func search(_ query: SearchQuery, page: Int) async throws -> SearchPage {
        switch behavior {
        case .succeed(let tracks):
            return SearchPage(items: tracks.map { .track($0) }, page: page, hasMore: false, totalCount: tracks.count)
        case .fail(let error):
            throw error
        case .delay(let nanoseconds, let tracks):
            try await Task.sleep(nanoseconds: nanoseconds)
            return SearchPage(items: tracks.map { .track($0) }, page: page, hasMore: false, totalCount: tracks.count)
        }
    }
}

enum Sample {
    static func track(_ n: Int, source: SourceID = .openverse) -> PlayableTrack {
        PlayableTrack(
            id: "\(source.rawValue):\(n)",
            source: source,
            title: "Song \(n)",
            artist: "Artist",
            streamURL: URL(string: "https://example.org/\(n).mp3")
        )
    }

    static func tracks(_ count: Int) -> [PlayableTrack] {
        (1...count).map { track($0) }
    }
}
