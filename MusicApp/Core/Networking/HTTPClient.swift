import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP abstraction so sources can be tested with canned responses.
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

enum MusicSourceError: Error, Equatable, LocalizedError, Sendable {
    case http(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    case decoding(String)
    case api(String)
    case missingAPIKey
    case unsupported
    case network(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .http(let code): return "服务器返回错误（HTTP \(code)）"
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                return "请求太频繁，请 \(Int(retryAfter.rounded(.up))) 秒后再试"
            }
            return "请求太频繁，请稍后再试"
        case .notFound: return "没有找到内容"
        case .decoding: return "无法解析服务器返回的数据"
        case .api(let message): return "接口错误：\(message)"
        case .missingAPIKey: return "需要先在设置里填写 API Key"
        case .unsupported: return "该来源不支持此操作"
        case .network(let message): return "网络错误：\(message)"
        case .cancelled: return "已取消"
        }
    }

    /// Maps any thrown error into a `MusicSourceError`.
    static func wrap(_ error: Error) -> MusicSourceError {
        if let error = error as? MusicSourceError { return error }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return .cancelled }
            return .network(urlError.localizedDescription)
        }
        if error is DecodingError { return .decoding(String(describing: error)) }
        return .network(error.localizedDescription)
    }
}

struct URLSessionHTTPClient: HTTPClient {
    static let userAgent = "MusicApp/1.0 (iOS; https://github.com/diegozzzzds/blank-app)"

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MusicSourceError.network("无效的响应")
            }
            return (data, http)
        } catch {
            throw MusicSourceError.wrap(error)
        }
    }
}

extension HTTPClient {
    /// Performs the request, maps HTTP errors, and decodes JSON.
    func decode<T: Decodable>(_ type: T.Type, for request: URLRequest, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let data = try await checkedData(for: request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MusicSourceError.decoding(String(describing: error))
        }
    }

    /// Performs the request and throws for non-2xx responses.
    func checkedData(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await self.data(for: request)
        try Self.validate(response)
        return data
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 404:
            throw MusicSourceError.notFound
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw MusicSourceError.rateLimited(retryAfter: retry)
        default:
            throw MusicSourceError.http(response.statusCode)
        }
    }
}

enum RequestBuilder {
    /// Builds a GET request. Query items with nil values are skipped.
    static func get(_ base: String, _ items: [(String, String?)], timeout: TimeInterval = 15) -> URLRequest {
        var components = URLComponents(string: base)!
        let queryItems = items.compactMap { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        // URLComponents leaves "+" unescaped, which many servers decode as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
