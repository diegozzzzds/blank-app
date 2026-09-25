import Foundation

/// A Creative Commons (or public-domain) license attached to a track.
struct LicenseInfo: Hashable, Codable, Sendable {
    /// Lowercased code such as "by", "by-nc-sa", "cc0", "pdm".
    var code: String
    var version: String?
    var url: URL?

    init(code: String, version: String? = nil, url: URL? = nil) {
        self.code = code.lowercased()
        self.version = version?.isEmpty == true ? nil : version
        self.url = url
    }

    var displayName: String {
        switch code {
        case "cc0": return "CC0"
        case "pdm", "publicdomain": return "公有领域"
        default:
            let name = "CC " + code.uppercased()
            if let version { return "\(name) \(version)" }
            return name
        }
    }

    /// NonCommercial licenses forbid commercial reuse.
    var isNonCommercial: Bool { code.contains("nc") }

    /// Public-domain style licenses do not require attribution.
    var requiresAttribution: Bool { !(code == "cc0" || code == "pdm" || code == "publicdomain") }

    /// Parses URLs like `https://creativecommons.org/licenses/by-nc-sa/3.0/`
    /// or `http://creativecommons.org/publicdomain/zero/1.0/`.
    static func fromURL(_ string: String?) -> LicenseInfo? {
        guard let string, !string.isEmpty else { return nil }
        let url = URL(string: string)
        let parts = string
            .lowercased()
            .split(separator: "/")
            .map(String.init)
        if let index = parts.firstIndex(of: "licenses"), index + 1 < parts.count {
            let code = parts[index + 1]
            let version = index + 2 < parts.count ? parts[index + 2] : nil
            let isVersion = version.map { $0.first?.isNumber == true } ?? false
            return LicenseInfo(code: code, version: isVersion ? version : nil, url: url)
        }
        if let index = parts.firstIndex(of: "publicdomain"), index + 1 < parts.count {
            let kind = parts[index + 1]
            let version = index + 2 < parts.count ? parts[index + 2] : nil
            if kind == "zero" { return LicenseInfo(code: "cc0", version: version, url: url) }
            if kind == "mark" { return LicenseInfo(code: "pdm", version: version, url: url) }
            return LicenseInfo(code: "publicdomain", url: url)
        }
        return nil
    }
}
