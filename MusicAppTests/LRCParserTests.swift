import XCTest
@testable import MusicApp

final class LRCParserTests: XCTestCase {
    func testParsesBasicLines() {
        let doc = LRCParser.parse("[00:01.00]Hello\n[00:05.50]World")
        XCTAssertTrue(doc.isSynced)
        XCTAssertEqual(doc.lines.map(\.text), ["Hello", "World"])
        XCTAssertEqual(doc.lines[0].time, 1.0, accuracy: 0.001)
        XCTAssertEqual(doc.lines[1].time, 5.5, accuracy: 0.001)
        XCTAssertEqual(doc.lines.map(\.id), [0, 1])
    }

    func testTimestampFormats() {
        XCTAssertEqual(LRCParser.parseTimestamp("1:02")!, 62, accuracy: 0.001)
        XCTAssertEqual(LRCParser.parseTimestamp("01:02.5")!, 62.5, accuracy: 0.001)
        XCTAssertEqual(LRCParser.parseTimestamp("01:02.50")!, 62.5, accuracy: 0.001)
        XCTAssertEqual(LRCParser.parseTimestamp("01:02.505")!, 62.505, accuracy: 0.0001)
        XCTAssertEqual(LRCParser.parseTimestamp("01:02:50")!, 62.5, accuracy: 0.001)
        XCTAssertEqual(LRCParser.parseTimestamp("123:00.00")!, 7380, accuracy: 0.001)
        XCTAssertNil(LRCParser.parseTimestamp("ar:Someone"))
        XCTAssertNil(LRCParser.parseTimestamp("01:75.00"))
        XCTAssertNil(LRCParser.parseTimestamp(":01"))
        XCTAssertNil(LRCParser.parseTimestamp("01:0a"))
    }

    func testMultipleTimestampsPerLineAreSorted() {
        let doc = LRCParser.parse("[00:10.00][00:30.00]Chorus\n[00:20.00]Verse")
        XCTAssertEqual(doc.lines.map(\.text), ["Chorus", "Verse", "Chorus"])
        XCTAssertEqual(doc.lines.map(\.time), [10, 20, 30])
    }

    func testMetadataTagsAndPositiveOffset() {
        let doc = LRCParser.parse("[ar:Artist]\n[ti:Title]\n[offset:+500]\n[00:02.00]Line")
        XCTAssertEqual(doc.metadata["ar"], "Artist")
        XCTAssertEqual(doc.metadata["ti"], "Title")
        XCTAssertEqual(doc.lines.count, 1)
        // Positive offset shows lyrics earlier.
        XCTAssertEqual(doc.lines[0].time, 1.5, accuracy: 0.001)
    }

    func testNegativeOffsetAndClampToZero() {
        let later = LRCParser.parse("[offset:-1000]\n[00:02.00]Line")
        XCTAssertEqual(later.lines[0].time, 3.0, accuracy: 0.001)
        let clamped = LRCParser.parse("[offset:5000]\n[00:02.00]Line")
        XCTAssertEqual(clamped.lines[0].time, 0, accuracy: 0.001)
    }

    func testBOMAndCRLF() {
        let doc = LRCParser.parse("\u{FEFF}[00:01.00]One\r\n[00:02.00]Two\r[00:03.00]Three")
        XCTAssertEqual(doc.lines.map(\.text), ["One", "Two", "Three"])
    }

    func testKeepsEmptyLinesForInstrumentalBreaks() {
        let doc = LRCParser.parse("[00:01.00]Sing\n[00:05.00]\n[00:09.00]Again")
        XCTAssertEqual(doc.lines.map(\.text), ["Sing", "", "Again"])
    }

    func testStripsEnhancedWordTimings() {
        let doc = LRCParser.parse("[00:01.00]<00:01.00>Hello <00:01.50>World")
        XCTAssertEqual(doc.lines.first?.text, "Hello World")
        XCTAssertEqual(LRCParser.stripWordTimings("a < b > c"), "a < b > c")
    }

    func testNonTimestampBracketAfterTimestampIsText() {
        let doc = LRCParser.parse("[00:01.00][Chorus] la la")
        XCTAssertEqual(doc.lines.first?.text, "[Chorus] la la")
    }

    func testFallsBackToPlainText() {
        let doc = LRCParser.parse("[ti:Song]\n\nFirst line\nSecond line\n\n")
        XCTAssertFalse(doc.isSynced)
        XCTAssertEqual(doc.lines.map(\.text), ["First line", "Second line"])
        XCTAssertNil(doc.lineIndex(at: 10))
    }

    func testLineIndexBoundaries() {
        let doc = LRCParser.parse("[00:05.00]A\n[00:10.00]B\n[00:15.00]C")
        XCTAssertNil(doc.lineIndex(at: 0))
        XCTAssertNil(doc.lineIndex(at: 4.99))
        XCTAssertEqual(doc.lineIndex(at: 5), 0)
        XCTAssertEqual(doc.lineIndex(at: 9.99), 0)
        XCTAssertEqual(doc.lineIndex(at: 10), 1)
        XCTAssertEqual(doc.lineIndex(at: 14), 1)
        XCTAssertEqual(doc.lineIndex(at: 15), 2)
        XCTAssertEqual(doc.lineIndex(at: 999), 2)
        XCTAssertNil(LyricsDocument.empty.lineIndex(at: 1))
    }

    func testSerializedRoundTrip() {
        let original = LRCParser.parse("[00:01.25]One\n[01:02.50]Two")
        let reparsed = LRCParser.parse(original.serialized())
        XCTAssertEqual(reparsed.lines, original.lines)
        let plain = LRCParser.plain("a\nb")
        XCTAssertEqual(plain.serialized(), "a\nb")
    }

    func testUnsyncedCopy() {
        let doc = LRCParser.parse("[00:01.00]One").unsynced()
        XCTAssertFalse(doc.isSynced)
        XCTAssertNil(doc.lineIndex(at: 5))
    }

    func testTextDecodingUTF8AndUTF16() {
        let utf8BOM = Data([0xEF, 0xBB, 0xBF]) + Data("[00:01.00]你好".utf8)
        XCTAssertEqual(TextDecoding.decodeText(utf8BOM), "[00:01.00]你好")
        var utf16 = Data([0xFF, 0xFE])
        utf16.append("晴天".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(TextDecoding.decodeText(utf16), "晴天")
    }
}
