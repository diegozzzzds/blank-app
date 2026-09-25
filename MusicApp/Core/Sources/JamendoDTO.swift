import Foundation

/// Jamendo reports errors with HTTP 200 and `headers.status == "failed"`.
struct JamendoResponse: Decodable {
    struct Headers: Decodable {
        let status: String?
        let code: Int?
        let error_message: String?
        let results_count: Int?
        let results_fullcount: Int?
    }

    let headers: Headers
    @LossyArray var results: [JamendoTrackDTO]
}

struct JamendoTrackDTO: Decodable, Sendable {
    struct MusicInfo: Decodable, Sendable {
        struct Tags: Decodable, Sendable {
            let genres: [String]?
        }

        let tags: Tags?
    }

    let id: FlexibleString
    let name: String?
    let duration: FlexibleString?
    let artist_name: String?
    let album_name: String?
    let album_image: String?
    let image: String?
    let audio: String?
    let audiodownload: String?
    let audiodownload_allowed: Bool?
    let license_ccurl: String?
    let shareurl: String?
    let releasedate: String?
    let musicinfo: MusicInfo?
}
