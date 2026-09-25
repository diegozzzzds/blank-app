import Foundation

enum FileNaming {
    /// Removes characters that are invalid in file names and trims the length.
    static func sanitize(_ name: String, maxLength: Int = 120) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = name.unicodeScalars
            .map { invalid.contains($0) ? " " : String($0) }
            .joined()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let trimmed = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "未命名" : trimmed
    }

    /// Returns "base.ext", or "base (1).ext", "base (2).ext"... if the name already exists.
    static func uniqueFilename(base: String, ext: String, exists: (String) -> Bool) -> String {
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        func name(_ suffix: String) -> String {
            cleanExt.isEmpty ? base + suffix : "\(base)\(suffix).\(cleanExt)"
        }
        var candidate = name("")
        var counter = 1
        while exists(candidate) {
            candidate = name(" (\(counter))")
            counter += 1
        }
        return candidate
    }

    /// Maps an audio MIME type to a file extension that AVFoundation recognises.
    static func fileExtension(forMIME mime: String?) -> String? {
        guard let mime = mime?.lowercased().split(separator: ";").first.map({ $0.trimmingCharacters(in: .whitespaces) }) else {
            return nil
        }
        switch mime {
        case "audio/mpeg", "audio/mp3", "audio/mpeg3", "audio/x-mpeg": return "mp3"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": return "m4a"
        case "audio/aac", "audio/x-aac", "audio/aacp": return "aac"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave": return "wav"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        case "audio/x-caf": return "caf"
        default: return nil
        }
    }

    /// Known audio extensions AVPlayer can play.
    static let playableExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4b"]

    /// Builds `https://archive.org/download/<identifier>/<file>`, percent-encoding each path segment.
    static func iaDownloadURL(identifier: String, filename: String) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#;/")
        func encode(_ segment: Substring) -> String {
            String(segment).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(segment)
        }
        let path = filename.split(separator: "/", omittingEmptySubsequences: true).map(encode).joined(separator: "/")
        return URL(string: "https://archive.org/download/\(encode(Substring(identifier)))/\(path)")!
    }
}
