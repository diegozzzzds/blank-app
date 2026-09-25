import Foundation

enum DurationParser {
    /// Parses "04:29", "1:02:03" or "234.34" into seconds. Returns nil for anything else.
    static func seconds(_ string: String?) -> TimeInterval? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        if string.contains(":") {
            let parts = string.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count) else { return nil }
            var total: TimeInterval = 0
            for part in parts {
                guard let value = TimeInterval(part), value >= 0 else { return nil }
                total = total * 60 + value
            }
            return total
        }
        guard let value = TimeInterval(string), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
