import XCTest
@testable import MusicApp

final class UtilTests: XCTestCase {
    func testDurationParser() {
        XCTAssertEqual(DurationParser.seconds("04:29"), 269)
        XCTAssertEqual(DurationParser.seconds("1:02:03"), 3723)
        XCTAssertEqual(DurationParser.seconds("234.34"), 234.34)
        XCTAssertNil(DurationParser.seconds(nil))
        XCTAssertNil(DurationParser.seconds(""))
        XCTAssertNil(DurationParser.seconds("abc"))
        XCTAssertNil(DurationParser.seconds("1:2:3:4"))
    }

    func testTimeFormatting() {
        XCTAssertEqual(TimeFormatting.clock(0), "0:00")
        XCTAssertEqual(TimeFormatting.clock(185.9), "3:05")
        XCTAssertEqual(TimeFormatting.clock(3723), "1:02:03")
        XCTAssertEqual(TimeFormatting.clock(.nan), "--:--")
        XCTAssertEqual(TimeFormatting.clock(.infinity), "--:--")
        XCTAssertNil(TimeFormatting.clock(Optional<TimeInterval>.none))
    }

    func testArtworkURL() {
        let url = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/ab/cd/100x100bb.jpg")!
        XCTAssertEqual(ArtworkURL.itunes(url, size: 600).lastPathComponent, "600x600bb.jpg")
        let other = URL(string: "https://example.org/cover.jpg")!
        XCTAssertEqual(ArtworkURL.itunes(other), other)
    }

    func testSanitizeAndUniqueFilenames() {
        XCTAssertEqual(FileNaming.sanitize("AC/DC: Back?"), "AC DC Back")
        XCTAssertEqual(FileNaming.sanitize("  ..  "), "未命名")
        XCTAssertEqual(FileNaming.sanitize(String(repeating: "a", count: 300)).count, 120)
        let existing: Set<String> = ["Song.mp3", "Song (1).mp3"]
        XCTAssertEqual(FileNaming.uniqueFilename(base: "Song", ext: "mp3", exists: existing.contains), "Song (2).mp3")
        XCTAssertEqual(FileNaming.uniqueFilename(base: "New", ext: ".m4a", exists: existing.contains), "New.m4a")
    }

    func testMIMEExtensions() {
        XCTAssertEqual(FileNaming.fileExtension(forMIME: "audio/mpeg"), "mp3")
        XCTAssertEqual(FileNaming.fileExtension(forMIME: "audio/mp4; charset=binary"), "m4a")
        XCTAssertEqual(FileNaming.fileExtension(forMIME: "AUDIO/FLAC"), "flac")
        XCTAssertNil(FileNaming.fileExtension(forMIME: "text/html"))
        XCTAssertNil(FileNaming.fileExtension(forMIME: nil))
    }

    func testLicenseParsing() {
        let by = LicenseInfo.fromURL("http://creativecommons.org/licenses/by-nc-sa/3.0/")
        XCTAssertEqual(by?.code, "by-nc-sa")
        XCTAssertEqual(by?.version, "3.0")
        XCTAssertEqual(by?.displayName, "CC BY-NC-SA 3.0")
        XCTAssertTrue(by?.isNonCommercial ?? false)
        XCTAssertTrue(by?.requiresAttribution ?? false)

        let zero = LicenseInfo.fromURL("https://creativecommons.org/publicdomain/zero/1.0/")
        XCTAssertEqual(zero?.displayName, "CC0")
        XCTAssertFalse(zero?.requiresAttribution ?? true)

        XCTAssertEqual(LicenseInfo.fromURL("https://creativecommons.org/publicdomain/mark/1.0/")?.displayName, "公有领域")
        XCTAssertEqual(LicenseInfo.fromURL("https://creativecommons.org/licenses/by/")?.displayName, "CC BY")
        XCTAssertNil(LicenseInfo.fromURL("https://example.org/terms"))
        XCTAssertNil(LicenseInfo.fromURL(nil))
    }

    func testSearchHistory() {
        var history = SearchHistory(limit: 3)
        history.record("  周杰伦 ")
        history.record("jazz")
        history.record("Jazz")
        history.record("")
        XCTAssertEqual(history.items, ["Jazz", "周杰伦"])
        history.record("a")
        history.record("b")
        XCTAssertEqual(history.items, ["b", "a", "Jazz"])
        history.remove("a")
        XCTAssertEqual(history.items, ["b", "Jazz"])
        history.clear()
        XCTAssertTrue(history.items.isEmpty)
    }

    func testSearchHistoryStoreRoundTrip() {
        let suite = "test.history.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SearchHistoryStore(defaults: defaults)
        XCTAssertTrue(store.load().items.isEmpty)
        var history = SearchHistory()
        history.record("hello")
        store.save(history)
        XCTAssertEqual(store.load().items, ["hello"])
    }

    func testContainsCJK() {
        XCTAssertTrue(SearchQuery(text: "周杰伦").containsCJK)
        XCTAssertTrue(SearchQuery(text: "ドラえもん").containsCJK)
        XCTAssertFalse(SearchQuery(text: "Jay Chou").containsCJK)
    }

    func testJamendoDedup() {
        let openverse = PlayableTrack(
            id: "openverse:1", source: .openverse, title: "A", artist: "B",
            streamURL: URL(string: "https://prod-1.storage.jamendo.com/?trackid=923463&format=mp32"),
            webPageURL: URL(string: "https://www.jamendo.com/track/923463")
        )
        let other = PlayableTrack(id: "openverse:2", source: .openverse, title: "C", artist: "D",
                                  streamURL: URL(string: "https://cdn.freesound.org/x.mp3"))
        let jamendo = PlayableTrack(id: "jamendo:923463", source: .jamendo, title: "A", artist: "B")
        XCTAssertEqual(Dedup.jamendoTrackID(streamURL: openverse.streamURL, webPageURL: nil), "923463")
        XCTAssertEqual(Dedup.jamendoTrackID(streamURL: nil, webPageURL: openverse.webPageURL), "923463")
        let filtered = Dedup.removingJamendoDuplicates(from: [.track(openverse), .track(other)], jamendo: [.track(jamendo)])
        XCTAssertEqual(filtered.map(\.id), ["openverse:2"])
    }

    func testPlayableTrackSubtitleAndAttribution() {
        var track = PlayableTrack(id: "x", source: .openverse, title: "T", artist: "A", album: "Al")
        XCTAssertEqual(track.subtitle, "A · Al")
        track.album = "T"
        XCTAssertEqual(track.subtitle, "A")
        track.license = LicenseInfo(code: "by", version: "4.0")
        XCTAssertEqual(track.attributionText, "\"T\" by A (CC BY 4.0)")
        track.attribution = "Custom"
        XCTAssertEqual(track.attributionText, "Custom")
    }

    func testLossyArraySkipsBadElements() throws {
        struct Item: Decodable { let n: Int }
        struct Wrapper: Decodable { @LossyArray var items: [Item] }
        let json = #"{"items":[{"n":1},{"n":"x"},"str",{"n":3},null]}"#
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
        XCTAssertEqual(wrapper.items.map(\.n), [1, 3])
        let missing = try JSONDecoder().decode(Wrapper.self, from: Data("{}".utf8))
        XCTAssertTrue(missing.items.isEmpty)
    }
}
