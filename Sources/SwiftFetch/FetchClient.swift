import Foundation

/// A lightweight HTTP client built on top of `URLSession` with async/await.
public struct FetchClient {
    /// Retry behavior configuration for `FetchClient`.
    public struct RetryPolicy {
        /// Enables or disables retries. When `false`, requests run once.
        public var isEnabled: Bool
        /// Maximum number of retry attempts (not counting the initial try).
        public var maxRetries: Int
        /// Initial backoff delay in seconds before the first retry.
        public var initialBackoff: TimeInterval
        /// Multiplicative factor applied to the delay after each retry.
        public var backoffMultiplier: Double
        /// Status codes that are considered retryable.
        public var retryableStatusCodes: Set<Int>
        /// `URLError` codes that should be retried.
        public var retryableURLErrorCodes: Set<URLError.Code>

        public init(
            isEnabled: Bool = false,
            maxRetries: Int = 2,
            initialBackoff: TimeInterval = 0.2,
            backoffMultiplier: Double = 2.0,
            retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504],
            retryableURLErrorCodes: Set<URLError.Code> = [
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .notConnectedToInternet,
                .dnsLookupFailed
            ]
        ) {
            self.isEnabled = isEnabled
            self.maxRetries = maxRetries
            self.initialBackoff = initialBackoff
            self.backoffMultiplier = backoffMultiplier
            self.retryableStatusCodes = retryableStatusCodes
            self.retryableURLErrorCodes = retryableURLErrorCodes
        }
    }

    /// Immutable configuration for a `FetchClient`.
    public struct Configuration {
        /// The base URL used when requests specify a relative path.
        public var baseURL: URL?
        /// Headers automatically merged into every request.
        public var defaultHeaders: [String: String]
        /// The underlying session, useful for testing via `URLProtocol` injection.
        public var session: URLSession
        /// Optional retry policy; disabled by default.
        public var retryPolicy: RetryPolicy

        public init(
            baseURL: URL? = nil,
            defaultHeaders: [String: String] = [:],
            session: URLSession = .shared,
            retryPolicy: RetryPolicy = .init()
        ) {
            self.baseURL = baseURL
            self.defaultHeaders = defaultHeaders
            self.session = session
            self.retryPolicy = retryPolicy
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

        let policy = configuration.retryPolicy
        var attempt = 0

        while true {
            do {
                return try await performOnce(urlRequest)
            } catch let error as FetchError {
                guard shouldRetry(error: error, attempt: attempt, policy: policy) else {
                    throw error
                }
                attempt += 1
                let delay = backoffNanoseconds(forAttempt: attempt, policy: policy)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
            }
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

    /// Executes the HTTP request once and maps errors into `FetchError`.
    private func performOnce(_ urlRequest: URLRequest) async throws -> FetchResponse {
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

    private func shouldRetry(error: FetchError, attempt: Int, policy: RetryPolicy) -> Bool {
        guard policy.isEnabled, attempt < policy.maxRetries else { return false }

        switch error {
        case let .statusCode(code, _):
            return policy.retryableStatusCodes.contains(code)
        case let .requestFailed(underlying):
            if let urlError = underlying as? URLError {
                return policy.retryableURLErrorCodes.contains(urlError.code)
            }
            return false
        default:
            return false
        }
    }

    private func backoffNanoseconds(forAttempt attempt: Int, policy: RetryPolicy) -> UInt64 {
        guard policy.initialBackoff > 0 else { return 0 }
        let exponent = max(Double(attempt - 1), 0)
        let seconds = policy.initialBackoff * pow(policy.backoffMultiplier, exponent)
        return UInt64(seconds * 1_000_000_000)
    }
}

