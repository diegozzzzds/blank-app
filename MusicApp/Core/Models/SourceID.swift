import Foundation

/// Where a track comes from. Raw values are persisted, so never rename them.
enum SourceID: String, Codable, CaseIterable, Hashable, Sendable {
    case itunes
    case openverse
    case internetArchive
    case jamendo
    case local

    var displayName: String {
        switch self {
        case .itunes: return "iTunes 试听"
        case .openverse: return "Openverse"
        case .internetArchive: return "Internet Archive"
        case .jamendo: return "Jamendo"
        case .local: return "本地"
        }
    }

    var shortName: String {
        switch self {
        case .itunes: return "iTunes"
        case .openverse: return "Openverse"
        case .internetArchive: return "Archive"
        case .jamendo: return "Jamendo"
        case .local: return "本地"
        }
    }

    /// iTunes only exposes 30-second previews.
    var isPreviewOnly: Bool { self == .itunes }

    /// Whether full tracks from this source may be saved for offline listening.
    var supportsDownload: Bool {
        switch self {
        case .openverse, .internetArchive, .jamendo: return true
        case .itunes, .local: return false
        }
    }

    /// Remote sources that take part in online search, in display order.
    static let remoteSources: [SourceID] = [.itunes, .jamendo, .openverse, .internetArchive]
}
