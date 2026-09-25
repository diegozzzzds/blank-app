import Foundation

struct OpenverseSearchResponse: Decodable {
    let result_count: Int?
    let page_count: Int?
    let page_size: Int?
    let page: Int?
    @LossyArray var results: [OpenverseAudioDTO]
}

struct OpenverseAudioDTO: Decodable, Sendable {
    struct AudioSet: Decodable, Sendable {
        let title: String?
    }

    let id: String
    let title: String?
    let foreign_landing_url: String?
    let url: String?
    let creator: String?
    let license: String?
    let license_version: String?
    let license_url: String?
    let provider: String?
    let source: String?
    let category: String?
    let genres: [String]?
    let filetype: String?
    let attribution: String?
    let audio_set: AudioSet?
    /// Milliseconds.
    let duration: Double?
    let thumbnail: String?
}
