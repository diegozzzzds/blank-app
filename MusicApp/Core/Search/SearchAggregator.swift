import Foundation

enum SearchEvent: Sendable {
    case page(SourceID, SearchPage)
    case failed(SourceID, MusicSourceError)
}

/// Runs a query against several sources concurrently and streams each source's first page
/// as soon as it arrives, so one slow or failing source never blocks the others.
struct SearchAggregator: Sendable {
    let sources: [any MusicSource]

    init(sources: [any MusicSource]) {
        self.sources = sources
    }

    func source(for id: SourceID) -> (any MusicSource)? {
        sources.first { $0.id == id }
    }

    func search(_ query: SearchQuery, in ids: Set<SourceID>) -> AsyncStream<SearchEvent> {
        let selected = sources.filter { ids.contains($0.id) }
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: SearchEvent?.self) { group in
                    for source in selected {
                        group.addTask {
                            do {
                                let page = try await source.search(query, page: 1)
                                return .page(source.id, page)
                            } catch {
                                let wrapped = MusicSourceError.wrap(error)
                                return wrapped == .cancelled ? nil : .failed(source.id, wrapped)
                            }
                        }
                    }
                    for await event in group {
                        if let event { continuation.yield(event) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func loadPage(_ page: Int, source id: SourceID, query: SearchQuery) async throws -> SearchPage {
        guard let source = source(for: id) else { throw MusicSourceError.unsupported }
        do {
            return try await source.search(query, page: page)
        } catch {
            throw MusicSourceError.wrap(error)
        }
    }
}
