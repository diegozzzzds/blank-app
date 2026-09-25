import Foundation
import UIKit

/// Loads and caches artwork images (for Now Playing info; views use AsyncImage).
actor ArtworkLoader {
    private let cache = NSCache<NSString, UIImage>()
    private let files: FileLocations
    private let session: URLSession

    init(files: FileLocations, session: URLSession = .shared) {
        self.files = files
        self.session = session
        cache.countLimit = 50
    }

    func image(for track: PlayableTrack) async -> UIImage? {
        if let filename = track.localArtworkFilename {
            let key = "file:\(filename)" as NSString
            if let cached = cache.object(forKey: key) { return cached }
            if let image = UIImage(contentsOfFile: files.artworkURL(filename).path) {
                cache.setObject(image, forKey: key)
                return image
            }
        }
        guard let url = track.artworkURL else { return nil }
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }
}
