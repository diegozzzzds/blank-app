import Foundation

struct ITunesSearchResponse: Decodable {
    let resultCount: Int?
    @LossyArray var results: [ITunesTrackDTO]
}

struct ITunesTrackDTO: Decodable, Sendable {
    let wrapperType: String?
    let kind: String?
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
    let previewUrl: String?
    let trackTimeMillis: Int?
    let primaryGenreName: String?
    let releaseDate: String?
    let trackViewUrl: String?
}
