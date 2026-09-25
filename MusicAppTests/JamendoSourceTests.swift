import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MusicApp

final class JamendoSourceTests: XCTestCase {
    func testMissingClientIDThrowsWithoutRequest() async {
        let http = MockHTTPClient(status: 200)
        let source = JamendoSource(http: http, clientID: "  ")
        do {
            _ = try await source.search(SearchQuery(text: "pop"), page: 1)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MusicSourceError, .missingAPIKey)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testRequestParameters() {
        let request = JamendoSource.makeSearchRequest(query: SearchQuery(text: "rock"), page: 2, clientID: "abc")
        XCTAssertEqual(request.query("client_id"), "abc")
        XCTAssertEqual(request.query("search"), "rock")
        XCTAssertEqual(request.query("offset"), "20")
        XCTAssertEqual(request.query("limit"), "20")
        XCTAssertEqual(request.query("format"), "json")
        XCTAssertEqual(request.query("include"), "musicinfo licenses")

        XCTAssertEqual(JamendoSource.makeSearchRequest(query: SearchQuery(text: "x", scope: .song), page: 1, clientID: "a").query("namesearch"), "x")
        XCTAssertEqual(JamendoSource.makeSearchRequest(query: SearchQuery(text: "x", scope: .artist), page: 1, clientID: "a").query("artist_name"), "x")
        XCTAssertEqual(JamendoSource.makeSearchRequest(query: SearchQuery(text: "x", scope: .album), page: 1, clientID: "a").query("album_name"), "x")
    }

    func testSearchMapsTracks() async throws {
        let source = JamendoSource(http: try MockHTTPClient(fixture: "jamendo_tracks"), clientID: "abc")
        let page = try await source.search(SearchQuery(text: "summer"), page: 1)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.totalCount, 45)
        let tracks = page.items.compactMap(\.track)
        XCTAssertEqual(tracks.count, 2, "the track without audio is dropped")

        let first = tracks[0]
        XCTAssertEqual(first.id, "jamendo:1532771")
        XCTAssertEqual(first.duration, 185)
        XCTAssertEqual(first.artworkURL?.absoluteString, "https://usercontent.jamendo.com?type=album&id=42&width=300",
                       "empty image falls back to album_image")
        XCTAssertNotNil(first.downloadURL)
        XCTAssertEqual(first.license?.displayName, "CC BY-SA 3.0")
        XCTAssertEqual(first.genre, "pop")

        let second = tracks[1]
        XCTAssertEqual(second.id, "jamendo:99", "numeric id decoded")
        XCTAssertEqual(second.duration, 240, "string duration decoded")
        XCTAssertNil(second.downloadURL, "download not allowed")
        XCTAssertNil(second.album, "empty album name becomes nil")
    }

    func testErrorsReportedWithHTTP200() async {
        let source = JamendoSource(http: try! MockHTTPClient(fixture: "jamendo_error"), clientID: "bad")
        do {
            _ = try await source.search(SearchQuery(text: "x"), page: 1)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MusicSourceError, .api("client_id 无效"))
        }
    }
}
