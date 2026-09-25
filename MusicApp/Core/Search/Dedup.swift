import Foundation

enum Dedup {
    /// Openverse's `category=music` results are Jamendo tracks. Extracts the Jamendo track id from
    /// "https://prod-1.storage.jamendo.com/?trackid=923463&format=mp32" or
    /// "https://www.jamendo.com/track/923463".
    static func jamendoTrackID(streamURL: URL?, webPageURL: URL?) -> String? {
        if let streamURL,
           streamURL.host?.contains("jamendo.com") == true,
           let components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == "trackid" })?.value,
           !value.isEmpty {
            return value
        }
        if let webPageURL, webPageURL.host?.contains("jamendo.com") == true {
            let parts = webPageURL.pathComponents
            if let index = parts.firstIndex(of: "track"), index + 1 < parts.count {
                return parts[index + 1]
            }
        }
        return nil
    }

    /// Removes Openverse items that duplicate tracks already listed from Jamendo.
    static func removingJamendoDuplicates(from openverse: [SearchResultItem], jamendo: [SearchResultItem]) -> [SearchResultItem] {
        let jamendoIDs = Set(jamendo.compactMap { item -> String? in
            guard let track = item.track, track.id.hasPrefix("jamendo:") else { return nil }
            return String(track.id.dropFirst("jamendo:".count))
        })
        guard !jamendoIDs.isEmpty else { return openverse }
        return openverse.filter { item in
            guard let track = item.track,
                  let id = jamendoTrackID(streamURL: track.streamURL, webPageURL: track.webPageURL) else { return true }
            return !jamendoIDs.contains(id)
        }
    }
}
