import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MusicApp

final class InternetArchiveSourceTests: XCTestCase {
    func testQueryStringScopesAndFilter() {
        let all = InternetArchiveSource.makeQueryString(SearchQuery(text: "jazz piano"))
        XCTAssertTrue(all.hasPrefix("(jazz piano) AND mediatype:audio"))
        XCTAssertTrue(all.contains("-collection:(podcasts"))
        XCTAssertTrue(InternetArchiveSource.makeQueryString(SearchQuery(text: "x", scope: .artist)).hasPrefix("creator:(x)"))
        XCTAssertTrue(InternetArchiveSource.makeQueryString(SearchQuery(text: "x", scope: .song)).hasPrefix("title:(x)"))
        XCTAssertTrue(InternetArchiveSource.makeQueryString(SearchQuery(text: "x", scope: .album)).hasPrefix("title:(x)"))
    }

    func testLuceneCharactersAreRemoved() {
        XCTAssertEqual(InternetArchiveSource.sanitizeLucene("AC/DC: \"Back\" (in) black!"), "AC DC Back in black")
        XCTAssertEqual(InternetArchiveSource.sanitizeLucene("***"), "")
    }

    func testSearchRequestHasRepeatedFieldParameters() {
        let request = InternetArchiveSource.makeSearchRequest(query: SearchQuery(text: "jazz"), page: 3)
        XCTAssertEqual(request.queryValues("fl[]"), ["identifier", "title", "creator", "licenseurl", "year"])
        XCTAssertEqual(request.query("page"), "3")
        XCTAssertEqual(request.query("rows"), "20")
        XCTAssertEqual(request.query("output"), "json")
    }

    func testSearchMapsDocsToCollections() async throws {
        let source = InternetArchiveSource(http: try MockHTTPClient(fixture: "ia_advancedsearch"))
        let page = try await source.search(SearchQuery(text: "jazz"), page: 1)
        XCTAssertEqual(page.items.count, 6)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.totalCount, 88942)

        guard case .collection(let first) = page.items[0] else { return XCTFail("expected a collection") }
        XCTAssertEqual(first.id, "ia:JonathanShowPulin4Jazz.151219.8")
        XCTAssertEqual(first.year, "2015", "numeric year decoded as text")
        XCTAssertEqual(first.artworkURL?.absoluteString, "https://archive.org/services/img/JonathanShowPulin4Jazz.151219.8")

        guard case .collection(let licensed) = page.items[4] else { return XCTFail("expected a collection") }
        XCTAssertEqual(licensed.license?.displayName, "CC BY-SA 3.0")

        guard case .collection(let multi) = page.items[5] else { return XCTFail("expected a collection") }
        XCTAssertEqual(multi.title, "Array Title")
        XCTAssertEqual(multi.subtitle, "Alice, Bob")
        XCTAssertEqual(multi.license?.displayName, "CC0")
    }

    func testAlbumFileSelectionOrderingAndEncoding() throws {
        let response = try FixtureLoader.decode(IAMetadataResponse.self, from: "ia_metadata_album")
        let tracks = InternetArchiveSource.tracks(from: response, identifier: "test_album", fallback: nil)
        XCTAssertEqual(tracks.map(\.title), ["First", "Second", "Last Song", "03 Song #1?"])

        XCTAssertEqual(tracks[0].artist, "Band A")
        XCTAssertEqual(tracks[0].duration ?? 0, 269, accuracy: 0.01)
        XCTAssertEqual(tracks[0].album, "Test Album")
        XCTAssertEqual(tracks[0].license?.displayName, "CC BY-NC-SA 3.0")

        // The FLAC original is represented by its VBR MP3 derivative, not the 64kbps one.
        // Its tags (title, track number) are inherited from the original.
        XCTAssertEqual(tracks[1].id, "ia:test_album/02 Second.mp3")
        XCTAssertEqual(tracks[1].duration ?? 0, 200, accuracy: 0.01)
        XCTAssertEqual(tracks[1].artist, "Band A, Guest B", "falls back to the item creator")

        XCTAssertEqual(tracks[2].duration ?? 0, 123.5, accuracy: 0.01)
        XCTAssertEqual(tracks[3].duration ?? 0, 3723, accuracy: 0.01)
        XCTAssertEqual(
            tracks[3].streamURL?.absoluteString,
            "https://archive.org/download/test_album/Disc%202/03%20Song%20%231%3F.mp3"
        )
        XCTAssertEqual(tracks[3].downloadURL, tracks[3].streamURL)
        XCTAssertTrue(tracks.allSatisfy { $0.source == .internetArchive && !$0.isPreview })
    }

    func testSingleRealItem() throws {
        let response = try FixtureLoader.decode(IAMetadataResponse.self, from: "ia_metadata_single")
        let tracks = InternetArchiveSource.tracks(from: response, identifier: "FeelinStrange", fallback: nil)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].title, "feelin strange")
        XCTAssertEqual(tracks[0].duration ?? 0, 252, accuracy: 0.01)
        XCTAssertEqual(tracks[0].streamURL?.absoluteString, "https://archive.org/download/FeelinStrange/SomeKindaJazz.mp3")
    }

    func testMissingItemReturnsNoTracks() async throws {
        let source = InternetArchiveSource(http: try MockHTTPClient(fixture: "ia_metadata_empty"))
        let collection = RemoteCollection(id: "ia:missing", source: .internetArchive, title: "Missing")
        let tracks = try await source.tracks(in: collection)
        XCTAssertTrue(tracks.isEmpty)
    }

    func testMetadataRequestUsesIdentifier() async throws {
        let http = try MockHTTPClient(fixture: "ia_metadata_single")
        let source = InternetArchiveSource(http: http)
        let collection = RemoteCollection(id: "ia:FeelinStrange", source: .internetArchive, title: "x")
        _ = try await source.tracks(in: collection)
        XCTAssertEqual(http.requests.first?.url?.absoluteString, "https://archive.org/metadata/FeelinStrange")
    }
}
