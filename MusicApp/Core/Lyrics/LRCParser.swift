import Foundation

/// Parses LRC lyrics. Hand-written scanner (no regex) so it runs anywhere Foundation does.
///
/// Supported: `[m:ss]`, `[mm:ss.x]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, `[mm:ss:xx]`, several timestamps
/// per line, ID tags (`[ar:]`, `[ti:]`, `[offset:]`...), enhanced word tags (`<mm:ss.xx>`, stripped),
/// BOM and CRLF. Files without any timestamp fall back to plain text.
enum LRCParser {
    static func parse(_ text: String) -> LyricsDocument {
        var metadata: [String: String] = [:]
        var timed: [(time: TimeInterval, order: Int, text: String)] = []
        var order = 0

        for rawLine in normalizedLines(text) {
            var rest = Substring(rawLine).drop(while: { $0 == " " || $0 == "\t" })
            var stamps: [TimeInterval] = []

            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let content = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseTimestamp(content) {
                    stamps.append(time)
                } else if let (key, value) = parseTag(content) {
                    metadata[key] = value
                } else {
                    break
                }
                rest = rest[rest.index(after: close)...]
            }

            guard !stamps.isEmpty else { continue }
            let lyric = stripWordTimings(String(rest)).trimmingCharacters(in: .whitespaces)
            for time in stamps {
                timed.append((time, order, lyric))
                order += 1
            }
        }

        guard !timed.isEmpty else { return plain(text) }

        // Positive offset (milliseconds) makes lyrics appear earlier.
        let offsetMilliseconds = metadata["offset"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        let shift: TimeInterval = offsetMilliseconds / 1000
        let sorted = timed.sorted { lhs, rhs in
            lhs.time == rhs.time ? lhs.order < rhs.order : lhs.time < rhs.time
        }
        var lines: [LyricLine] = []
        lines.reserveCapacity(sorted.count)
        for (index, entry) in sorted.enumerated() {
            let time: TimeInterval = max(0, entry.time - shift)
            lines.append(LyricLine(id: index, time: time, text: entry.text))
        }
        return LyricsDocument(lines: lines, isSynced: true, metadata: metadata)
    }

    /// Unsynced lyrics: one line per text line, ID tags removed, surrounding blank lines trimmed.
    static func plain(_ text: String) -> LyricsDocument {
        var texts: [String] = []
        for rawLine in normalizedLines(text) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"),
               parseTag(Substring(trimmed.dropFirst().dropLast())) != nil {
                continue
            }
            texts.append(stripWordTimings(trimmed))
        }
        while texts.first?.isEmpty == true { texts.removeFirst() }
        while texts.last?.isEmpty == true { texts.removeLast() }
        let lines = texts.enumerated().map { LyricLine(id: $0.offset, time: 0, text: $0.element) }
        return LyricsDocument(lines: lines, isSynced: false)
    }

    // MARK: - Helpers

    static func normalizedLines(_ text: String) -> [String] {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// "mm:ss", "mm:ss.xx", "mm:ss:xx" -> seconds.
    static func parseTimestamp(_ content: Substring) -> TimeInterval? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let minutesText = parts[0]
        guard !minutesText.isEmpty, minutesText.allSatisfy(\.isASCIIDigit), let minutes = Double(minutesText) else {
            return nil
        }

        var secondsText = parts[1]
        var fractionText: Substring = ""
        if parts.count == 3 {
            fractionText = parts[2]
        } else if let dot = secondsText.firstIndex(of: ".") {
            fractionText = secondsText[secondsText.index(after: dot)...]
            secondsText = secondsText[..<dot]
        }
        guard !secondsText.isEmpty, secondsText.count <= 2, secondsText.allSatisfy(\.isASCIIDigit),
              let seconds = Double(secondsText), seconds < 60 else { return nil }
        guard fractionText.allSatisfy(\.isASCIIDigit) else { return nil }
        let fraction = fractionText.isEmpty ? 0 : (Double("0." + fractionText) ?? 0)
        return minutes * 60 + seconds + fraction
    }

    /// "ar:Artist" -> ("ar", "Artist"). Keys are letters only (plus '#').
    static func parseTag(_ content: Substring) -> (String, String)? {
        guard let colon = content.firstIndex(of: ":") else { return nil }
        let key = content[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0 == "#" }) else { return nil }
        let value = content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    /// Removes enhanced-LRC word timings such as "<00:12.34>".
    static func stripWordTimings(_ text: String) -> String {
        guard text.contains("<") else { return text }
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            if let close = rest[afterOpen...].firstIndex(of: ">"),
               parseTimestamp(rest[afterOpen..<close]) != nil {
                rest = rest[rest.index(after: close)...]
            } else {
                result += "<"
                rest = rest[afterOpen...]
            }
        }
        result += rest
        return result.replacingOccurrences(of: "  ", with: " ")
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
