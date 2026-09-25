import Foundation

/// Where audio and artwork files live. Only file *names* are persisted, because the
/// app container path changes between installs and updates.
struct FileLocations: Sendable {
    /// Documents/Music: visible in the Files app (UIFileSharingEnabled).
    let musicDirectory: URL
    /// Application Support/Artwork: private.
    let artworkDirectory: URL
    /// Documents root, scanned for files the user dropped in via the Files app or Finder.
    let documentsDirectory: URL

    static let standard: FileLocations = {
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let locations = FileLocations(
            musicDirectory: documents.appendingPathComponent("Music", isDirectory: true),
            artworkDirectory: support.appendingPathComponent("Artwork", isDirectory: true),
            documentsDirectory: documents
        )
        locations.ensureDirectories()
        return locations
    }()

    func ensureDirectories() {
        let manager = FileManager.default
        try? manager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        try? manager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }

    func musicURL(_ filename: String) -> URL {
        musicDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    func artworkURL(_ filename: String) -> URL {
        artworkDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    func musicFileExists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: musicURL(filename).path)
    }

    /// A file name in Documents/Music that does not exist yet.
    func uniqueMusicFilename(base: String, ext: String) -> String {
        FileNaming.uniqueFilename(base: FileNaming.sanitize(base), ext: ext) { musicFileExists($0) }
    }

    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Total size in bytes of the files in a directory (non-recursive enough for our flat folders).
    static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
