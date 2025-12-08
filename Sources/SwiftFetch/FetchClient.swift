import Foundation

/// A lightweight HTTP client built on top of `URLSession` with async/await.
public struct FetchClient {
    /// Immutable configuration for a `FetchClient`.
    public struct Configuration {
        /// The base URL used when requests specify a relative path.
        public var baseURL: URL?
        /// Headers automatically merged into every request.
        public var defaultHeaders: [String: String]
        /// The underlying session, useful for testing via `URLProtocol` injection.
        public var session: URLSession

        public init(
            baseURL: URL? = nil,
            defaultHeaders: [String: String] = [:],
            session: URLSession = .shared
        ) {
            self.baseURL = baseURL
            self.defaultHeaders = defaultHeaders
            self.session = session
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Perform the request and return a typed `FetchResponse`.
    /// - Parameters:
    ///   - request: The request definition.
    ///   - query: Optional query parameters to append to the URL.
    public func perform(
        _ request: FetchRequest,
        query: [String: String]? = nil
    ) async throws -> FetchResponse {
        let url = try makeURL(from: request.url, query: query)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body

        let headers = configuration.defaultHeaders.merging(request.headers) { _, new in new }
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await configuration.session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FetchError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw FetchError.statusCode(httpResponse.statusCode, data: data)
            }
            return FetchResponse(data: data, response: httpResponse)
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.requestFailed(underlying: error)
        }
    }

    /// Decode JSON from a response into the requested type.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - response: The raw response data and metadata.
    ///   - decoder: Optional decoder for custom strategies.
    public func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from response: FetchResponse,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch {
            throw FetchError.decodingFailed(underlying: error)
        }
    }

    /// Builds a URL by combining the configured base URL, request path, and query parameters.
    private func makeURL(from url: URL, query: [String: String]? = nil) throws -> URL {
        let resolvedURL: URL

        if url.scheme == nil {
            guard let baseURL = configuration.baseURL else {
                throw FetchError.invalidURL
            }
            var path = url.path
            if path.hasPrefix("/") {
                path.removeFirst()
            }
            resolvedURL = baseURL.appendingPathComponent(path)
        } else {
            resolvedURL = url
        }

        guard var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false) else {
            throw FetchError.invalidURL
        }

        if let query {
            let items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            components.queryItems = (components.queryItems ?? []) + items
        }

        guard let finalURL = components.url else {
            throw FetchError.invalidURL
        }

        return finalURL
    }
}

