import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MusicApp

final class LRCLIBClientTests: XCTestCase {
    func testGetRequest() {
        let request = LRCLIBClient.makeGetRequest(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269.6)
        XCTAssertEqual(request.url?.path, "/api/get")
        XCTAssertEqual(request.query("track_name"), "晴天")
        XCTAssertEqual(request.query("artist_name"), "周杰伦")
        XCTAssertEqual(request.query("album_name"), "叶惠美")
        XCTAssertEqual(request.query("duration"), "270")

        let minimal = LRCLIBClient.makeGetRequest(title: "a", artist: "b", album: " ", duration: nil)
        XCTAssertNil(minimal.query("album_name"))
        XCTAssertNil(minimal.query("duration"))
    }

    func testExactMatchIsUsed() async throws {
        let http = try MockHTTPClient(fixture: "lrclib_get")
        let client = LRCLIBClient(http: http)
        let record = try await client.fetch(title: "晴天", artist: "周杰伦", album: nil, duration: 270)
        XCTAssertEqual(record?.id, 17788)
        let doc = try XCTUnwrap(record?.document)
        XCTAssertTrue(doc.isSynced)
        XCTAssertEqual(doc.lines.first?.time ?? 0, 29.36, accuracy: 0.001)
        XCTAssertEqual(http.requests.count, 1)
    }

    func testFallsBackToSearchOn404() async throws {
        let notFound = try FixtureLoader.data("lrclib_404")
        let results = try FixtureLoader.data("lrclib_search")
        let http = MockHTTPClient { request in
            request.url?.path == "/api/get"
                ? .init(data: notFound, status: 404)
                : .init(data: results)
        }
        let client = LRCLIBClient(http: http)
        let record = try await client.fetch(title: "晴天 (Live)", artist: "周杰伦", album: nil, duration: 270)
        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(http.requests.last?.query("track_name"), "晴天", "decorations removed for search")
        let match = try XCTUnwrap(record)
        XCTAssertEqual(match.trackName, "晴天")
        XCTAssertEqual(match.duration ?? 0, 270, accuracy: 3)
        XCTAssertTrue(match.hasSynced)
    }

    func testBestMatchRequiresTitle() throws {
        let records = try FixtureLoader.decode([LRCLIBRecord].self, from: "lrclib_search")
        XCTAssertNil(LRCLIBClient.bestMatch(records, title: "完全不同", artist: "周杰伦", duration: 270))
        XCTAssertEqual(LRCLIBClient.bestMatch(records, title: "Other Song", artist: "周杰伦", duration: nil)?.id, 1)
    }

    func testCleanedTitle() {
        XCTAssertEqual(LRCLIBClient.cleanedTitle("晴天 (Live)"), "晴天")
        XCTAssertEqual(LRCLIBClient.cleanedTitle("Song (feat. Someone) [Explicit]"), "Song")
        XCTAssertEqual(LRCLIBClient.cleanedTitle("稻香（伴奏）"), "稻香")
        XCTAssertEqual(LRCLIBClient.cleanedTitle("Yesterday - Remastered 2009"), "Yesterday")
        XCTAssertEqual(LRCLIBClient.cleanedTitle("Part One - Part Two"), "Part One - Part Two")
        XCTAssertEqual(LRCLIBClient.cleanedTitle("(Intro)"), "(Intro)")
    }

    func testNormalize() {
        XCTAssertEqual(LRCLIBClient.normalize("Hello, World!"), "helloworld")
        XCTAssertEqual(LRCLIBClient.normalize(" 晴 天 "), "晴天")
    }

    func testInstrumentalRecordHasNoDocument() throws {
        let json = #"{"id":5,"trackName":"Intro","artistName":"X","instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#
        let record = try JSONDecoder().decode(LRCLIBRecord.self, from: Data(json.utf8))
        XCTAssertTrue(record.isInstrumental)
        XCTAssertNil(record.document)
    }
}
