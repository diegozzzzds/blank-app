import Foundation

enum ArtworkURL {
    /// iTunes artwork URLs end in e.g. ".../100x100bb.jpg"; the size can be changed freely.
    static func itunes(_ url: URL, size: Int = 600) -> URL {
        let last = url.lastPathComponent
        guard let xIndex = last.firstIndex(of: "x"),
              let bbRange = last.range(of: "bb.", range: xIndex..<last.endIndex) else { return url }
        let width = last[last.startIndex..<xIndex]
        let height = last[last.index(after: xIndex)..<bbRange.lowerBound]
        guard !width.isEmpty, !height.isEmpty,
              width.allSatisfy(\.isNumber), height.allSatisfy(\.isNumber) else { return url }
        let newLast = "\(size)x\(size)" + last[bbRange.lowerBound...]
        return url.deletingLastPathComponent().appendingPathComponent(newLast)
    }
}
