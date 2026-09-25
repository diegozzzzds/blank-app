import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MusicApp

/// Returns canned responses and records every request it receives.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    struct Response {
        var data: Data
        var status: Int = 200
        var headers: [String: String] = [:]
    }

    typealias Handler = (URLRequest) throws -> Response

    private let lock = NSLock()
    private let handler: Handler
    private var recorded: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Always answers with the same fixture.
    convenience init(fixture: String, status: Int = 200, headers: [String: String] = [:]) throws {
        let data = try FixtureLoader.data(fixture)
        self.init { _ in Response(data: data, status: status, headers: headers) }
    }

    /// Always answers with an empty body and the given status.
    convenience init(status: Int, headers: [String: String] = [:]) {
        self.init { _ in Response(data: Data(), status: status, headers: headers) }
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let response = try handler(request)
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        return (response.data, http)
    }
}

extension URLRequest {
    /// Query items of the request URL, for assertions.
    var queryItems: [URLQueryItem] {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    }

    func query(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    func queryValues(_ name: String) -> [String] {
        queryItems.filter { $0.name == name }.compactMap(\.value)
    }
}
