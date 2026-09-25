import Foundation

enum TimeFormatting {
    /// "3:05", "1:02:03", or "--:--" for invalid values.
    static func clock(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "--:--" }
        let total = Int(time.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Optional convenience used by list rows.
    static func clock(_ time: TimeInterval?) -> String? {
        guard let time, time.isFinite, time > 0 else { return nil }
        return clock(time)
    }
}
