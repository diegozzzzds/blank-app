import Foundation

struct LyricLine: Identifiable, Hashable, Sendable {
    var id: Int
    /// Seconds from the start of the track. 0 for unsynced lyrics.
    var time: TimeInterval
    var text: String
}

struct LyricsDocument: Hashable, Sendable {
    var lines: [LyricLine]
    var isSynced: Bool
    /// ID tags such as ar, ti, al, by, offset.
    var metadata: [String: String]

    init(lines: [LyricLine], isSynced: Bool, metadata: [String: String] = [:]) {
        self.lines = lines
        self.isSynced = isSynced
        self.metadata = metadata
    }

    static let empty = LyricsDocument(lines: [], isSynced: false)

    var isEmpty: Bool { lines.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// Index of the line that should be highlighted at `time`, or nil before the first line.
    func lineIndex(at time: TimeInterval) -> Int? {
        guard isSynced, let first = lines.first, time >= first.time else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// A copy that is displayed statically (e.g. lyrics for a 30-second preview).
    func unsynced() -> LyricsDocument {
        var copy = self
        copy.isSynced = false
        return copy
    }

    /// Serialises back to LRC (synced) or plain text, for caching.
    func serialized() -> String {
        guard isSynced else { return lines.map(\.text).joined(separator: "\n") }
        return lines.map { line in
            let centis = Int((line.time * 100).rounded())
            let minutes = centis / 6000
            let seconds = (centis % 6000) / 100
            let fraction = centis % 100
            return String(format: "[%02d:%02d.%02d]", minutes, seconds, fraction) + line.text
        }.joined(separator: "\n")
    }
}
