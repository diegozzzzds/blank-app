import Foundation

/// One slot in the queue. Has its own ID so the same song can be queued twice.
struct QueueEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let track: PlayableTrack

    init(track: PlayableTrack, id: UUID = UUID()) {
        self.id = id
        self.track = track
    }
}

/// Pure play-queue state machine: ordering, shuffle and repeat. No AVFoundation here.
///
/// `entries` keeps the original order; `order` is the play order (indices into `entries`);
/// `position` is the index into `order` of the current entry.
struct PlayQueue: Equatable, Sendable {
    private(set) var entries: [QueueEntry] = []
    private(set) var order: [Int] = []
    private(set) var position: Int?
    var repeatMode: RepeatMode = .off
    private(set) var isShuffled = false

    init() {}

    var isEmpty: Bool { entries.isEmpty }

    var current: QueueEntry? {
        guard let position, order.indices.contains(position) else { return nil }
        return entries[order[position]]
    }

    /// Entries that will play after the current one, in play order.
    var upNext: [QueueEntry] {
        guard let position else { return order.map { entries[$0] } }
        return order[(position + 1)...].map { entries[$0] }
    }

    /// Entries already played, in play order.
    var history: [QueueEntry] {
        guard let position else { return [] }
        return order[..<position].map { entries[$0] }
    }

    var hasNext: Bool {
        guard let position else { return false }
        return position + 1 < order.count || (repeatMode == .all && !order.isEmpty)
    }

    // MARK: - Replacing

    mutating func replace<G: RandomNumberGenerator>(
        with tracks: [PlayableTrack],
        startAt index: Int,
        shuffle: Bool,
        using generator: inout G
    ) {
        entries = tracks.map { QueueEntry(track: $0) }
        guard !entries.isEmpty else {
            order = []
            position = nil
            isShuffled = false
            return
        }
        let start = min(max(index, 0), entries.count - 1)
        isShuffled = shuffle
        if shuffle {
            var rest = Array(entries.indices).filter { $0 != start }
            rest.shuffle(using: &generator)
            order = [start] + rest
            position = 0
        } else {
            order = Array(entries.indices)
            position = start
        }
    }

    mutating func replace(with tracks: [PlayableTrack], startAt index: Int = 0, shuffle: Bool = false) {
        var generator = SystemRandomNumberGenerator()
        replace(with: tracks, startAt: index, shuffle: shuffle, using: &generator)
    }

    mutating func clear() {
        entries = []
        order = []
        position = nil
        isShuffled = false
    }

    // MARK: - Moving through the queue

    /// Moves to the next entry. `automatic` is true when the previous track finished by itself:
    /// then `.one` repeats the same entry. A manual "next" always moves on.
    /// Returns nil (and leaves the position unchanged) at the end with repeat off.
    @discardableResult
    mutating func advance(automatic: Bool) -> QueueEntry? {
        guard let position, !order.isEmpty else { return nil }
        if automatic && repeatMode == .one {
            return current
        }
        if position + 1 < order.count {
            self.position = position + 1
            return current
        }
        if repeatMode == .all || (repeatMode == .one && !automatic) {
            self.position = 0
            return current
        }
        return nil
    }

    /// Moves to the previous entry. Wraps to the end with repeat all; otherwise stays on the first.
    @discardableResult
    mutating func goBack() -> QueueEntry? {
        guard let position, !order.isEmpty else { return nil }
        if position > 0 {
            self.position = position - 1
        } else if repeatMode == .all {
            self.position = order.count - 1
        }
        return current
    }

    // MARK: - Shuffle

    mutating func setShuffle<G: RandomNumberGenerator>(_ on: Bool, using generator: inout G) {
        guard on != isShuffled else { return }
        isShuffled = on
        guard !entries.isEmpty else { return }
        let currentIndex = position.map { order[$0] }
        if on {
            var rest = Array(entries.indices)
            if let currentIndex { rest.removeAll { $0 == currentIndex } }
            rest.shuffle(using: &generator)
            if let currentIndex {
                order = [currentIndex] + rest
                position = 0
            } else {
                order = rest
            }
        } else {
            order = Array(entries.indices)
            position = currentIndex
        }
    }

    mutating func setShuffle(_ on: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffle(on, using: &generator)
    }

    // MARK: - Editing

    /// Inserts tracks right after the current entry.
    mutating func insertNext(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        let newIndices = appendEntries(tracks)
        guard let position else {
            order.append(contentsOf: newIndices)
            self.position = order.isEmpty ? nil : 0
            return
        }
        order.insert(contentsOf: newIndices, at: position + 1)
    }

    /// Appends tracks to the end of the queue.
    mutating func append(_ tracks: [PlayableTrack]) {
        guard !tracks.isEmpty else { return }
        let newIndices = appendEntries(tracks)
        order.append(contentsOf: newIndices)
        if position == nil { position = 0 }
    }

    /// Reorders the "up next" list. Offsets are relative to `upNext`.
    mutating func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = (position ?? -1) + 1
        guard base <= order.count else { return }
        var tail = Array(order[base...])
        let moving = source.filter { tail.indices.contains($0) }.map { tail[$0] }
        guard !moving.isEmpty else { return }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        for offset in source.sorted(by: >) where tail.indices.contains(offset) {
            tail.remove(at: offset)
        }
        let insertAt = min(max(adjustedDestination, 0), tail.count)
        tail.insert(contentsOf: moving, at: insertAt)
        order.replaceSubrange(base..., with: tail)
    }

    /// Removes entries from the "up next" list. Offsets are relative to `upNext`.
    mutating func removeUpNext(atOffsets offsets: IndexSet) {
        let base = (position ?? -1) + 1
        let orderPositions = offsets.map { base + $0 }.filter { order.indices.contains($0) }
        let removedEntryIndices = Set(orderPositions.map { order[$0] })
        guard !removedEntryIndices.isEmpty else { return }
        for index in orderPositions.sorted(by: >) {
            order.remove(at: index)
        }
        compact(removing: removedEntryIndices)
    }

    /// Jumps to an entry in the "up next" list, skipping the ones before it.
    @discardableResult
    mutating func jump(toUpNext offset: Int) -> QueueEntry? {
        let base = (position ?? -1) + 1
        let target = base + offset
        guard order.indices.contains(target) else { return nil }
        position = target
        return current
    }

    /// Jumps to an entry in play order (used by the queue list for history entries).
    @discardableResult
    mutating func jump(toEntryID id: UUID) -> QueueEntry? {
        guard let target = order.firstIndex(where: { entries[$0].id == id }) else { return nil }
        position = target
        return current
    }

    /// Removes every entry with the given track id (e.g. a deleted local file). Keeps position sensible.
    mutating func removeTracks(withID trackID: String) {
        let removed = Set(entries.indices.filter { entries[$0].track.id == trackID })
        guard !removed.isEmpty else { return }
        let currentIndex = position.map { order[$0] }
        var newPosition = position
        if let position {
            let removedBefore = order[..<position].filter { removed.contains($0) }.count
            newPosition = position - removedBefore
        }
        order.removeAll { removed.contains($0) }
        if let currentIndex, removed.contains(currentIndex) {
            // Current track removed: the entry that followed it takes its place.
            newPosition = order.isEmpty ? nil : min(newPosition ?? 0, order.count - 1)
        }
        position = order.isEmpty ? nil : newPosition
        compact(removing: removed)
    }

    /// Replaces the stored track value (e.g. after a download sets `localFilename`).
    mutating func updateTrack(_ track: PlayableTrack) {
        for index in entries.indices where entries[index].track.id == track.id {
            entries[index] = QueueEntry(track: track, id: entries[index].id)
        }
    }

    // MARK: - Private

    private mutating func appendEntries(_ tracks: [PlayableTrack]) -> [Int] {
        let start = entries.count
        entries.append(contentsOf: tracks.map { QueueEntry(track: $0) })
        return Array(start..<entries.count)
    }

    /// Drops removed entries and renumbers `order` accordingly.
    private mutating func compact(removing removed: Set<Int>) {
        var mapping: [Int: Int] = [:]
        var kept: [QueueEntry] = []
        for (index, entry) in entries.enumerated() where !removed.contains(index) {
            mapping[index] = kept.count
            kept.append(entry)
        }
        entries = kept
        order = order.compactMap { mapping[$0] }
        if entries.isEmpty {
            position = nil
        }
    }
}
