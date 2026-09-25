import Foundation

struct SourceCapabilities: Sendable {
    var supportedScopes: Set<SearchScope>
    var pageSize: Int
    var requiresAPIKey: Bool
}

/// A searchable online catalog. Implementations are plain structs so they can be recreated
/// whenever settings (country, API key) change.
protocol MusicSource: Sendable {
    var id: SourceID { get }
    var capabilities: SourceCapabilities { get }

    /// `page` is 1-based.
    func search(_ query: SearchQuery, page: Int) async throws -> SearchPage

    /// Expands a collection (e.g. an Internet Archive album) into playable tracks.
    func tracks(in collection: RemoteCollection) async throws -> [PlayableTrack]
}

extension MusicSource {
    func tracks(in collection: RemoteCollection) async throws -> [PlayableTrack] {
        throw MusicSourceError.unsupported
    }
}

/// Small async cache used by sources that fetch everything at once and page client-side.
actor ResultCache<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    private let limit: Int

    init(limit: Int = 8) {
        self.limit = limit
    }

    func value(for key: Key) -> Value? {
        storage[key]
    }

    func set(_ value: Value, for key: Key) {
        if storage[key] == nil {
            order.append(key)
            if order.count > limit {
                let evicted = order.removeFirst()
                storage[evicted] = nil
            }
        }
        storage[key] = value
    }
}
