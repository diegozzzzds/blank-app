import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MusicApp

final class OpenverseSourceTests: XCTestCase {
    func testRequestScopes() {
        let all = OpenverseSource.makeSearchRequest(query: SearchQuery(text: "piano"), page: 2)
        XCTAssertEqual(all.url?.host, "api.openverse.org")
        XCTAssertEqual(all.query("q"), "piano")
        XCTAssertEqual(all.query("page"), "2")
        XCTAssertEqual(all.query("page_size"), "20")
        XCTAssertEqual(all.query("category"), "music")

        let song = OpenverseSource.makeSearchRequest(query: SearchQuery(text: "rain", scope: .song), page: 1)
        XCTAssertEqual(song.query("title"), "rain")
        XCTAssertNil(song.query("q"), "q would silently override title")

        let artist = OpenverseSource.makeSearchRequest(query: SearchQuery(text: "bach", scope: .artist), page: 1)
        XCTAssertEqual(artist.query("creator"), "bach")
        XCTAssertNil(artist.query("q"))

        let everything = OpenverseSource.makeSearchRequest(
            query: SearchQuery(text: "birds", includeNonMusic: true), page: 1)
        XCTAssertNil(everything.query("category"))
    }

    func testMappingDropsOggAndFillsFallbacks() throws {
        let response = try FixtureLoader.decode(OpenverseSearchResponse.self, from: "openverse_music")
        XCTAssertEqual(response.results.count, 5)
        let tracks = OpenverseSource.map(response.results)
        XCTAssertEqual(tracks.count, 4, "the Ogg result is dropped")

        let first = tracks[0]
        XCTAssertEqual(first.source, .openverse)
        XCTAssertEqual(first.title, "Old Movie Ragtime Piano")
        XCTAssertEqual(first.artist, "Akashic Records")
        XCTAssertEqual(first.album, "Silent Movie Ragtime Piano")
        XCTAssertEqual(first.duration ?? 0, 72, accuracy: 0.01, "milliseconds converted to seconds")
        XCTAssertEqual(first.license?.displayName, "CC BY-NC-ND 3.0")
        XCTAssertTrue(first.license?.isNonCommercial ?? false)
        XCTAssertFalse(first.isPreview)
        XCTAssertTrue(first.isDownloadable)
        XCTAssertNotNil(first.attribution)
        XCTAssertEqual(first.genre, "jazz")

        let nulls = tracks[3]
        XCTAssertEqual(nulls.title, "未命名")
        XCTAssertEqual(nulls.artist, "未知艺术家")
        XCTAssertNil(nulls.duration)
        XCTAssertEqual(nulls.license?.displayName, "CC0")
    }

    func testSearchPagingAndDepthLimit() async throws {
        let http = try MockHTTPClient(fixture: "openverse_music")
        let source = OpenverseSource(http: http)
        let page = try await source.search(SearchQuery(text: "piano"), page: 1)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.totalCount, 240)

        let last = try await source.search(SearchQuery(text: "piano"), page: 12)
        XCTAssertFalse(last.hasMore, "page 12 of 12")

        let beyond = try await source.search(SearchQuery(text: "piano"), page: 13)
        XCTAssertTrue(beyond.items.isEmpty)
        XCTAssertEqual(http.requests.count, 2, "no request beyond the 240-result depth")
    }

    func testRateLimitHonoursRetryAfter() async {
        let source = OpenverseSource(http: MockHTTPClient(status: 429, headers: ["Retry-After": "30"]))
        do {
            _ = try await source.search(SearchQuery(text: "x"), page: 1)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MusicSourceError, .rateLimited(retryAfter: 30))
            XCTAssertNotNil((error as? MusicSourceError)?.errorDescription)
        }
    }

    func testUnauthorizedOnLaterPageMeansNoMore() async throws {
        let source = OpenverseSource(http: MockHTTPClient(status: 401))
        let page = try await source.search(SearchQuery(text: "x"), page: 5)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertFalse(page.hasMore)
    }
}
