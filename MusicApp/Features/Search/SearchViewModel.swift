import Foundation
import Observation

enum SourceFilter: Hashable {
    case all
    case only(SourceID)

    func includes(_ source: SourceID) -> Bool {
        switch self {
        case .all: return true
        case .only(let id): return id == source
        }
    }
}

/// State of one source's results.
struct SourceSectionState {
    enum Status: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var status: Status = .loading
    var items: [SearchResultItem] = []
    var page = 1
    var hasMore = false
    var totalCount: Int?
    var isLoadingMore = false
    var loadMoreError: String?
}

/// Aggregated search across the online sources and the local library.
@MainActor
@Observable
final class SearchViewModel {
    var text = ""
    var scope: SearchScope = .all
    var filter: SourceFilter = .all

    private(set) var submittedQuery: SearchQuery?
    private(set) var sections: [SourceID: SourceSectionState] = [:]
    private(set) var localResults: [PlayableTrack] = []
    private(set) var history: SearchHistory

    private let registry: SourceRegistry
    private let library: LibraryStore
    private let historyStore: SearchHistoryStore
    @ObservationIgnored private var searchTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var aggregator: SearchAggregator?

    init(registry: SourceRegistry, library: LibraryStore, historyStore: SearchHistoryStore = SearchHistoryStore()) {
        self.registry = registry
        self.library = library
        self.historyStore = historyStore
        self.history = historyStore.load()
    }

    /// Sources shown in the filter bar, in order: online sources, then the local library.
    var availableSources: [SourceID] {
        registry.availableRemoteSources + [.local]
    }

    /// Sources that take part in the current search.
    var visibleSources: [SourceID] {
        availableSources.filter { filter.includes($0) }
    }

    var hasSubmitted: Bool { submittedQuery != nil }

    /// Items to display for a source (Openverse hides tracks already listed from Jamendo).
    func items(for source: SourceID) -> [SearchResultItem] {
        guard let state = sections[source] else { return [] }
        if source == .openverse, let jamendo = sections[.jamendo] {
            return Dedup.removingJamendoDuplicates(from: state.items, jamendo: jamendo.items)
        }
        return state.items
    }

    func tracks(for source: SourceID) -> [PlayableTrack] {
        if source == .local { return localResults }
        return items(for: source).compactMap(\.track)
    }

    /// Hint shown for sources whose catalog is mostly English.
    func hint(for source: SourceID) -> String? {
        guard let query = submittedQuery, query.containsCJK else { return nil }
        switch source {
        case .openverse, .internetArchive, .jamendo:
            return "该来源以英文内容为主，试试英文关键词"
        default:
            return nil
        }
    }

    // MARK: - Actions

    func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history.record(trimmed)
        historyStore.save(history)
        run(SearchQuery(text: trimmed, scope: scope, includeNonMusic: registry.includeNonMusic))
    }

    /// Live search while typing (only iTunes and the library, to spare rate-limited sources).
    func liveSearch() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let query = SearchQuery(text: trimmed, scope: scope, includeNonMusic: registry.includeNonMusic)
        run(query, remote: visibleSources.filter { $0 == .itunes })
    }

    func search(_ term: String) {
        text = term
        submit()
    }

    /// Re-runs the current search after the scope changed.
    func scopeChanged() {
        guard let query = submittedQuery else { return }
        run(SearchQuery(text: query.text, scope: scope, includeNonMusic: registry.includeNonMusic))
    }

    /// Only fetches sources that have no results yet, so switching chips doesn't spend rate limits.
    func filterChanged() {
        guard let query = submittedQuery else { return }
        if filter.includes(.local), localResults.isEmpty {
            localResults = library.searchLibrary(query.text).map(\.playable)
        }
        let missing = visibleSources.filter { $0 != .local && sections[$0] == nil }
        guard !missing.isEmpty else { return }
        run(query, remote: missing, keepOthers: true)
    }

    func reset() {
        cancelSearches()
        submittedQuery = nil
        sections = [:]
        localResults = []
    }

    func removeFromHistory(_ term: String) {
        history.remove(term)
        historyStore.save(history)
    }

    func clearHistory() {
        history.clear()
        historyStore.save(history)
    }

    func retry(_ source: SourceID) {
        guard let query = submittedQuery else { return }
        run(query, remote: [source], keepOthers: true)
    }

    func loadMore(_ source: SourceID) async {
        guard let query = submittedQuery, var state = sections[source], state.hasMore, !state.isLoadingMore,
              let aggregator else { return }
        state.isLoadingMore = true
        state.loadMoreError = nil
        sections[source] = state
        do {
            let page = try await aggregator.loadPage(state.page + 1, source: source, query: query)
            guard submittedQuery == query, var current = sections[source] else { return }
            let known = Set(current.items.map(\.id))
            current.items += page.items.filter { !known.contains($0.id) }
            current.page = page.page
            current.hasMore = page.hasMore && !page.items.isEmpty
            current.isLoadingMore = false
            sections[source] = current
        } catch {
            guard submittedQuery == query, var current = sections[source] else { return }
            current.isLoadingMore = false
            let wrapped = MusicSourceError.wrap(error)
            if wrapped != .cancelled {
                current.loadMoreError = wrapped.errorDescription
            }
            sections[source] = current
        }
    }

    // MARK: - Private

    private func cancelSearches() {
        searchTasks.forEach { $0.cancel() }
        searchTasks.removeAll()
    }

    private func run(_ query: SearchQuery, remote: [SourceID]? = nil, keepOthers: Bool = false) {
        if !keepOthers || submittedQuery != query {
            cancelSearches()
        }
        submittedQuery = query

        let remoteSources = (remote ?? visibleSources).filter { $0 != .local }
        if !keepOthers {
            sections = [:]
        }
        for source in remoteSources {
            sections[source] = SourceSectionState()
        }
        if !keepOthers {
            localResults = filter.includes(.local) ? library.searchLibrary(query.text).map(\.playable) : []
        }
        guard !remoteSources.isEmpty else { return }

        let aggregator = registry.aggregator()
        self.aggregator = aggregator
        let stream = aggregator.search(query, in: Set(remoteSources))
        searchTasks.append(Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                self?.apply(event, for: query)
            }
        })
    }

    private func apply(_ event: SearchEvent, for query: SearchQuery) {
        guard submittedQuery == query else { return }
        switch event {
        case .page(let source, let page):
            sections[source] = SourceSectionState(
                status: .loaded,
                items: page.items,
                page: page.page,
                hasMore: page.hasMore,
                totalCount: page.totalCount
            )
        case .failed(let source, let error):
            var state = sections[source] ?? SourceSectionState()
            state.status = .failed(error.errorDescription ?? "搜索失败")
            sections[source] = state
        }
    }
}
