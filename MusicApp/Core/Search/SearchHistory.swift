import Foundation

/// Most-recent-first list of past search terms, de-duplicated case-insensitively.
struct SearchHistory: Codable, Equatable, Sendable {
    private(set) var items: [String] = []
    var limit = 20

    init(items: [String] = [], limit: Int = 20) {
        self.limit = limit
        for item in items.reversed() { record(item) }
    }

    mutating func record(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        items.insert(trimmed, at: 0)
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
    }

    mutating func remove(_ term: String) {
        items.removeAll { $0 == term }
    }

    mutating func clear() {
        items.removeAll()
    }
}

/// Persists `SearchHistory` as JSON in UserDefaults.
final class SearchHistoryStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "searchHistory") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> SearchHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(SearchHistory.self, from: data) else {
            return SearchHistory()
        }
        return history
    }

    func save(_ history: SearchHistory) {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: key)
        }
    }
}
