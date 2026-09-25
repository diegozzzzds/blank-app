import Foundation

struct IASearchResponse: Decodable {
    struct Body: Decodable {
        let numFound: Int
        let start: Int?
        @LossyArray var docs: [IADoc]
    }

    let response: Body
}

struct IADoc: Decodable, Sendable {
    let identifier: String
    let title: StringOrArray?
    let creator: StringOrArray?
    let licenseurl: StringOrArray?
    let year: FlexibleString?
}

/// `/metadata/{identifier}`. A missing item returns `{}` with HTTP 200, so everything is optional.
struct IAMetadataResponse: Decodable {
    let metadata: IAItemMetadata?
    @LossyArray var files: [IAFile]
}

struct IAItemMetadata: Decodable, Sendable {
    let title: StringOrArray?
    let creator: StringOrArray?
    let licenseurl: StringOrArray?
    let date: StringOrArray?
}

struct IAFile: Decodable, Sendable {
    let name: String
    let source: String?
    let format: String?
    let original: String?
    let length: FlexibleString?
    let title: StringOrArray?
    let creator: StringOrArray?
    let artist: StringOrArray?
    let album: StringOrArray?
    let track: FlexibleString?

    /// Fills missing tags from another file (used for derivatives of an original recording).
    func inheriting(from other: IAFile) -> IAFile {
        IAFile(
            name: name,
            source: source,
            format: format,
            original: original,
            length: length ?? other.length,
            title: title ?? other.title,
            creator: creator ?? other.creator,
            artist: artist ?? other.artist,
            album: album ?? other.album,
            track: track ?? other.track
        )
    }
}
