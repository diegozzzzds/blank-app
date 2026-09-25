import Foundation
import Observation

/// Builds the active sources from the current settings.
@MainActor
@Observable
final class SourceRegistry {
    let http: HTTPClient
    private let defaults: UserDefaults
    /// Shared so iTunes pages survive re-creating the source.
    private let itunesCache = ResultCache<String, [PlayableTrack]>()

    init(http: HTTPClient, defaults: UserDefaults = .standard) {
        self.http = http
        self.defaults = defaults
    }

    var jamendoClientID: String {
        (defaults.string(forKey: SettingsKey.jamendoClientID) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isJamendoEnabled: Bool { !jamendoClientID.isEmpty }

    var itunesCountry: String {
        defaults.string(forKey: SettingsKey.itunesCountry) ?? "HK"
    }

    var includeNonMusic: Bool {
        defaults.bool(forKey: SettingsKey.openverseIncludeNonMusic)
    }

    /// Remote sources available right now, in display order.
    var availableRemoteSources: [SourceID] {
        SourceID.remoteSources.filter { $0 != .jamendo || isJamendoEnabled }
    }

    func activeSources() -> [any MusicSource] {
        availableRemoteSources.compactMap { source(for: $0) }
    }

    func source(for id: SourceID) -> (any MusicSource)? {
        switch id {
        case .itunes: return ITunesSource(http: http, country: itunesCountry, cache: itunesCache)
        case .openverse: return OpenverseSource(http: http)
        case .internetArchive: return InternetArchiveSource(http: http)
        case .jamendo: return isJamendoEnabled ? JamendoSource(http: http, clientID: jamendoClientID) : nil
        case .local: return nil
        }
    }

    func aggregator() -> SearchAggregator {
        SearchAggregator(sources: activeSources())
    }
}
