import XCTest
@testable import MusicApp

final class SearchAggregatorTests: XCTestCase {
    private func collect(_ stream: AsyncStream<SearchEvent>) async -> [SearchEvent] {
        var events: [SearchEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    func testReportsEachSourceIndependently() async {
        let aggregator = SearchAggregator(sources: [
            StubSource(id: .openverse, behavior: .succeed([Sample.track(1)])),
            StubSource(id: .itunes, behavior: .fail(.rateLimited(retryAfter: nil))),
            StubSource(id: .internetArchive, behavior: .delay(50_000_000, [Sample.track(2), Sample.track(3)])),
        ])
        let events = await collect(aggregator.search(SearchQuery(text: "x"), in: [.openverse, .itunes, .internetArchive]))
        XCTAssertEqual(events.count, 3)

        var pages: [SourceID: Int] = [:]
        var failures: [SourceID: MusicSourceError] = [:]
        for event in events {
            switch event {
            case .page(let id, let page): pages[id] = page.items.count
            case .failed(let id, let error): failures[id] = error
            }
        }
        XCTAssertEqual(pages[.openverse], 1)
        XCTAssertEqual(pages[.internetArchive], 2)
        XCTAssertEqual(failures[.itunes], .rateLimited(retryAfter: nil))
    }

    func testOnlySelectedSourcesAreQueried() async {
        let aggregator = SearchAggregator(sources: [
            StubSource(id: .openverse, behavior: .succeed([Sample.track(1)])),
            StubSource(id: .itunes, behavior: .succeed([Sample.track(2)])),
        ])
        let events = await collect(aggregator.search(SearchQuery(text: "x"), in: [.itunes]))
        XCTAssertEqual(events.count, 1)
        if case .page(let id, _) = events.first {
            XCTAssertEqual(id, .itunes)
        } else {
            XCTFail("expected a page")
        }
    }

    func testCancelledErrorsAreDropped() async {
        let aggregator = SearchAggregator(sources: [
            StubSource(id: .openverse, behavior: .fail(.cancelled)),
        ])
        let events = await collect(aggregator.search(SearchQuery(text: "x"), in: [.openverse]))
        XCTAssertTrue(events.isEmpty)
    }

    func testLoadPage() async throws {
        let aggregator = SearchAggregator(sources: [
            StubSource(id: .openverse, behavior: .succeed([Sample.track(1)])),
        ])
        let page = try await aggregator.loadPage(2, source: .openverse, query: SearchQuery(text: "x"))
        XCTAssertEqual(page.page, 2)
        do {
            _ = try await aggregator.loadPage(1, source: .jamendo, query: SearchQuery(text: "x"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MusicSourceError, .unsupported)
        }
    }
}
