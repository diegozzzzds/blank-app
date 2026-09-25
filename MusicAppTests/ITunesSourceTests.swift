import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MusicApp

final class ITunesSourceTests: XCTestCase {
    func testRequestParameters() {
        let request = ITunesSource.makeSearchRequest(query: SearchQuery(text: " 周杰伦 ", scope: .artist), country: "HK")
        XCTAssertEqual(request.url?.host, "itunes.apple.com")
        XCTAssertEqual(request.query("term"), "周杰伦")
        XCTAssertEqual(request.query("media"), "music")
        XCTAssertEqual(request.query("entity"), "song")
        XCTAssertEqual(request.query("attribute"), "artistTerm")
        XCTAssertEqual(request.query("limit"), "200")
        XCTAssertEqual(request.query("country"), "HK")

        let all = ITunesSource.makeSearchRequest(query: SearchQuery(text: "a"), country: "US")
        XCTAssertNil(all.query("attribute"))
        let song = ITunesSource.makeSearchRequest(query: SearchQuery(text: "a", scope: .song), country: "US")
        XCTAssertEqual(song.query("attribute"), "songTerm")
        let album = ITunesSource.makeSearchRequest(query: SearchQuery(text: "a", scope: .album), country: "US")
        XCTAssertEqual(album.query("attribute"), "albumTerm")
    }

    func testPlusSignIsEncoded() {
        let request = ITunesSource.makeSearchRequest(query: SearchQuery(text: "C++"), country: "US")
        XCTAssertTrue(request.url!.absoluteString.contains("C%2B%2B"))
        XCTAssertEqual(request.query("term"), "C++")
    }

    func testChinaStorefrontIsReplaced() {
        let source = ITunesSource(http: MockHTTPClient(status: 200), country: "cn")
        XCTAssertEqual(source.country, "HK")
    }

    func testDecodingSkipsBrokenElementsAndMappingFilters() throws {
        let response = try FixtureLoader.decode(ITunesSearchResponse.self, from: "itunes_search")
        XCTAssertEqual(response.results.count, 6, "the element with a string trackId is skipped")
        let tracks = ITunesSource.map(response.results)
        // Dropped: missing previewUrl, music video, duplicate trackId.
        XCTAssertEqual(tracks.count, 3)
        let first = try XCTUnwrap(tracks.first)
        XCTAssertTrue(first.id.hasPrefix("itunes:"))
        XCTAssertEqual(first.source, .itunes)
        XCTAssertTrue(first.isPreview)
        XCTAssertNil(first.downloadURL)
        XCTAssertFalse(first.isDownloadable)
        XCTAssertEqual(first.artist, "周杰倫")
        XCTAssertNotNil(first.streamURL)
        XCTAssertTrue(first.artworkURL?.absoluteString.contains("600x600bb") ?? false)
        XCTAssertGreaterThan(first.duration ?? 0, 60, "duration is the full song, not the preview")
    }

    func testPagesClientSideAndCachesResults() async throws {
        let many = (1...60).map { n in
            """
            {"wrapperType":"track","kind":"song","trackId":\(n),"trackName":"S\(n)","artistName":"A",
             "previewUrl":"https://example.org/\(n).m4a","trackTimeMillis":200000}
            """
        }.joined(separator: ",")
        let body = Data("{\"resultCount\":60,\"results\":[\(many)]}".utf8)
        let http = MockHTTPClient { _ in .init(data: body) }
        let source = ITunesSource(http: http, country: "HK")
        let query = SearchQuery(text: "test")

        let page1 = try await source.search(query, page: 1)
        XCTAssertEqual(page1.items.count, 25)
        XCTAssertTrue(page1.hasMore)
        XCTAssertEqual(page1.totalCount, 60)
        let page3 = try await source.search(query, page: 3)
        XCTAssertEqual(page3.items.count, 10)
        XCTAssertFalse(page3.hasMore)
        let page4 = try await source.search(query, page: 4)
        XCTAssertTrue(page4.items.isEmpty)
        XCTAssertEqual(http.requests.count, 1, "later pages come from the cache")
    }

    func testForbiddenMeansRateLimited() async {
        let source = ITunesSource(http: MockHTTPClient(status: 403), country: "HK")
        do {
            _ = try await source.search(SearchQuery(text: "x"), page: 1)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MusicSourceError, .rateLimited(retryAfter: 60))
        }
    }

    func testEmptyQueryDoesNotHitNetwork() async throws {
        let http = MockHTTPClient(status: 500)
        let page = try await ITunesSource(http: http).search(SearchQuery(text: "   "), page: 1)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertTrue(http.requests.isEmpty)
    }
}
