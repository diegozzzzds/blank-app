import XCTest
@testable import MusicApp

final class PlayQueueTests: XCTestCase {
    private func titles(_ entries: [QueueEntry]) -> [String] {
        entries.map(\.track.title)
    }

    func testReplaceStartsAtIndex() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(4), startAt: 1)
        XCTAssertEqual(queue.current?.track.title, "Song 2")
        XCTAssertEqual(titles(queue.upNext), ["Song 3", "Song 4"])
        XCTAssertEqual(titles(queue.history), ["Song 1"])
    }

    func testReplaceClampsIndexAndHandlesEmpty() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(2), startAt: 10)
        XCTAssertEqual(queue.current?.track.title, "Song 2")
        queue.replace(with: [], startAt: 0)
        XCTAssertNil(queue.current)
        XCTAssertNil(queue.advance(automatic: true))
        XCTAssertNil(queue.goBack())
    }

    func testAdvanceStopsAtEndWithRepeatOff() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(2), startAt: 0)
        XCTAssertEqual(queue.advance(automatic: true)?.track.title, "Song 2")
        XCTAssertNil(queue.advance(automatic: true))
        XCTAssertEqual(queue.current?.track.title, "Song 2")
        XCTAssertFalse(queue.hasNext)
    }

    func testRepeatAllWraps() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(2), startAt: 1)
        queue.repeatMode = .all
        XCTAssertTrue(queue.hasNext)
        XCTAssertEqual(queue.advance(automatic: true)?.track.title, "Song 1")
        XCTAssertEqual(queue.goBack()?.track.title, "Song 2")
    }

    func testRepeatOneRepeatsAutomaticallyButManualNextMovesOn() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(3), startAt: 0)
        queue.repeatMode = .one
        XCTAssertEqual(queue.advance(automatic: true)?.track.title, "Song 1")
        XCTAssertEqual(queue.advance(automatic: false)?.track.title, "Song 2")
    }

    func testGoBackAtStartStaysWithRepeatOff() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(3), startAt: 0)
        XCTAssertEqual(queue.goBack()?.track.title, "Song 1")
    }

    func testShuffleKeepsCurrentFirstAndIsAPermutation() {
        var queue = PlayQueue()
        var rng = SeededGenerator(seed: 42)
        queue.replace(with: Sample.tracks(10), startAt: 3, shuffle: true, using: &rng)
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(queue.current?.track.title, "Song 4")
        XCTAssertEqual(queue.order.count, 10)
        XCTAssertEqual(Set(queue.order), Set(0..<10))
        XCTAssertEqual(queue.position, 0)
    }

    func testShuffleIsDeterministicWithSeed() {
        var a = PlayQueue()
        var b = PlayQueue()
        var rngA = SeededGenerator(seed: 7)
        var rngB = SeededGenerator(seed: 7)
        a.replace(with: Sample.tracks(8), startAt: 0, shuffle: true, using: &rngA)
        b.replace(with: Sample.tracks(8), startAt: 0, shuffle: true, using: &rngB)
        XCTAssertEqual(a.order, b.order)
    }

    func testToggleShuffleOnAndOffRestoresOrder() {
        var queue = PlayQueue()
        var rng = SeededGenerator(seed: 1)
        queue.replace(with: Sample.tracks(6), startAt: 2)
        queue.setShuffle(true, using: &rng)
        XCTAssertEqual(queue.current?.track.title, "Song 3")
        XCTAssertEqual(queue.position, 0)
        queue.advance(automatic: false)
        let playing = queue.current?.track.title
        queue.setShuffle(false, using: &rng)
        XCTAssertEqual(queue.order, Array(0..<6))
        XCTAssertEqual(queue.current?.track.title, playing)
    }

    func testInsertNextAndAppend() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(3), startAt: 0)
        queue.insertNext([Sample.track(10)])
        queue.append([Sample.track(11)])
        XCTAssertEqual(titles(queue.upNext), ["Song 10", "Song 2", "Song 3", "Song 11"])
    }

    func testInsertIntoEmptyQueueStartsIt() {
        var queue = PlayQueue()
        queue.insertNext([Sample.track(1)])
        XCTAssertEqual(queue.current?.track.title, "Song 1")
        var other = PlayQueue()
        other.append([Sample.track(2)])
        XCTAssertEqual(other.current?.track.title, "Song 2")
    }

    func testDuplicateTracksGetDistinctEntryIDs() {
        var queue = PlayQueue()
        let track = Sample.track(1)
        queue.replace(with: [track, track], startAt: 0)
        XCTAssertEqual(queue.entries.count, 2)
        XCTAssertNotEqual(queue.entries[0].id, queue.entries[1].id)
    }

    func testMoveUpNext() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(5), startAt: 0)
        // upNext: 2 3 4 5 -> move "Song 2" to the end.
        queue.moveUpNext(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(titles(queue.upNext), ["Song 3", "Song 4", "Song 5", "Song 2"])
        // Move last to front.
        queue.moveUpNext(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(titles(queue.upNext), ["Song 2", "Song 3", "Song 4", "Song 5"])
        XCTAssertEqual(queue.current?.track.title, "Song 1")
    }

    func testRemoveUpNext() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(5), startAt: 1)
        queue.removeUpNext(atOffsets: IndexSet([0, 2]))
        XCTAssertEqual(titles(queue.upNext), ["Song 4"])
        XCTAssertEqual(queue.current?.track.title, "Song 2")
        XCTAssertEqual(titles(queue.history), ["Song 1"])
        XCTAssertEqual(queue.entries.count, 3)
    }

    func testJumpToUpNext() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(5), startAt: 0)
        XCTAssertEqual(queue.jump(toUpNext: 2)?.track.title, "Song 4")
        XCTAssertEqual(titles(queue.upNext), ["Song 5"])
        XCTAssertNil(queue.jump(toUpNext: 5))
    }

    func testJumpToEntryID() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(3), startAt: 2)
        let first = queue.entries[0].id
        XCTAssertEqual(queue.jump(toEntryID: first)?.track.title, "Song 1")
    }

    func testRemoveTracksRemovesCurrentAndKeepsNextPlaying() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(4), startAt: 1)
        queue.removeTracks(withID: Sample.track(2).id)
        XCTAssertEqual(queue.current?.track.title, "Song 3")
        XCTAssertEqual(titles(queue.history), ["Song 1"])
        queue.removeTracks(withID: Sample.track(1).id)
        XCTAssertEqual(queue.current?.track.title, "Song 3")
        XCTAssertEqual(titles(queue.upNext), ["Song 4"])
    }

    func testRemovingEverythingEmptiesQueue() {
        var queue = PlayQueue()
        queue.replace(with: [Sample.track(1)], startAt: 0)
        queue.removeTracks(withID: Sample.track(1).id)
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isEmpty)
    }

    func testUpdateTrackKeepsEntryIDs() {
        var queue = PlayQueue()
        queue.replace(with: Sample.tracks(2), startAt: 0)
        let id = queue.entries[0].id
        var updated = Sample.track(1)
        updated.localFilename = "song.mp3"
        queue.updateTrack(updated)
        XCTAssertEqual(queue.entries[0].id, id)
        XCTAssertEqual(queue.current?.track.localFilename, "song.mp3")
    }

    func testRepeatModeCycle() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }
}
