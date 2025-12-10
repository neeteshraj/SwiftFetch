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
        /// Optional jitter range multiplier applied to the computed delay.
        /// A range like `0.8...1.2` randomly scales the backoff to avoid thundering herds.
        public var jitterRange: ClosedRange<Double>?
        /// Status codes that are considered retryable.
        public var retryableStatusCodes: Set<Int>
        /// `URLError` codes that should be retried.
        public var retryableURLErrorCodes: Set<URLError.Code>
        /// Optional hook to override the retry decision for a given attempt.
        public var shouldRetry: ((FetchError, Int) -> Bool)?

        public init(
            isEnabled: Bool = false,
            maxRetries: Int = 2,
            initialBackoff: TimeInterval = 0.2,
            backoffMultiplier: Double = 2.0,
            jitterRange: ClosedRange<Double>? = nil,
            retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504],
            retryableURLErrorCodes: Set<URLError.Code> = [
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .notConnectedToInternet,
                .dnsLookupFailed
            ],
            shouldRetry: ((FetchError, Int) -> Bool)? = nil
        ) {
            self.isEnabled = isEnabled
            self.maxRetries = maxRetries
            self.initialBackoff = initialBackoff
            self.backoffMultiplier = backoffMultiplier
            self.jitterRange = jitterRange
            self.retryableStatusCodes = retryableStatusCodes
            self.retryableURLErrorCodes = retryableURLErrorCodes
            self.shouldRetry = shouldRetry
        }
    }

    /// Immutable configuration for a `FetchClient`.
    public struct Configuration {
        /// The base URL used when requests specify a relative path.
        public var baseURL: URL?
        /// Headers automatically merged into every request.
        public var defaultHeaders: [String: String]
        /// Default query parameters merged into every request unless overridden.
        public var defaultQuery: [String: String]
        /// The underlying session, useful for testing via `URLProtocol` injection.
        public var session: URLSession
        /// Optional retry policy; disabled by default.
        public var retryPolicy: RetryPolicy
        /// Ordered interceptors that can adapt and observe requests.
        public var interceptors: [FetchInterceptor]
        /// Optional metrics hook invoked with timing and result details.
        public var metricsHandler: ((URLRequest, FetchResponse?, FetchError?, TimeInterval) -> Void)?

        public init(
            baseURL: URL? = nil,
            defaultHeaders: [String: String] = [:],
            defaultQuery: [String: String] = [:],
            session: URLSession = .shared,
            retryPolicy: RetryPolicy = .init(),
            interceptors: [FetchInterceptor] = [],
            metricsHandler: ((URLRequest, FetchResponse?, FetchError?, TimeInterval) -> Void)? = nil
        ) {
            self.baseURL = baseURL
            self.defaultHeaders = defaultHeaders
            self.defaultQuery = defaultQuery
            self.session = session
            self.retryPolicy = retryPolicy
            self.interceptors = interceptors
            self.metricsHandler = metricsHandler
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
        let policy = configuration.retryPolicy
        var attempt = 0
        while true {
            do {
                let resolvedQuery = mergeQueries(configuration.defaultQuery, query)
                let url = try makeURL(from: request.url, query: resolvedQuery)
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = request.method.rawValue
                urlRequest.httpBody = request.body
                if request.body == nil, let stream = request.bodyStream {
                    urlRequest.httpBodyStream = stream
                }
                if let cachePolicy = request.cachePolicy {
                    urlRequest.cachePolicy = cachePolicy
                }
                if let timeout = request.timeoutInterval {
                    urlRequest.timeoutInterval = timeout
                }

                let headers = configuration.defaultHeaders.merging(request.headers) { _, new in new }
                for (key, value) in headers {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }
                if let contentLength = request.contentLength {
                    urlRequest.setValue(String(contentLength), forHTTPHeaderField: "Content-Length")
                }

                let adaptedRequest = try await applyInterceptors(to: urlRequest)
                let start = Date()
                do {
                    let response = try await performOnce(adaptedRequest)
                    await notifyInterceptors(.success(response), for: adaptedRequest)
                    configuration.metricsHandler?(adaptedRequest, response, nil, Date().timeIntervalSince(start))
                    return response
                } catch let error as FetchError {
                    await notifyInterceptors(.failure(error), for: adaptedRequest)
                    configuration.metricsHandler?(adaptedRequest, nil, error, Date().timeIntervalSince(start))
                    guard shouldRetry(error: error, attempt: attempt, policy: policy) else {
                        throw error
                    }
                }
                attempt += 1
                let delay = backoffNanoseconds(forAttempt: attempt, policy: policy)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
            } catch let error as FetchError {
                throw error
            } catch {
                let wrapped = FetchError.requestFailed(underlying: error)
                if shouldRetry(error: wrapped, attempt: attempt, policy: policy) {
                    attempt += 1
                    let delay = backoffNanoseconds(forAttempt: attempt, policy: policy)
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: delay)
                    }
                    continue
                }
                throw wrapped
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

    /// Decode JSON from a response after applying a data transformer.
    /// Useful for envelopes or preprocessing (e.g. data unwrapping).
    public func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from response: FetchResponse,
        transform: (Data) throws -> Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        do {
            let transformed = try transform(response.data)
            return try decoder.decode(T.self, from: transformed)
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.decodingFailed(underlying: error)
        }
    }

    /// Decode JSON from a nested key path using `JSONSerialization` to unwrap the payload.
    public func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from response: FetchResponse,
        atKeyPath keyPath: [String],
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        do {
            let unwrapped = try extractJSON(from: response.data, keyPath: keyPath)
            return try decoder.decode(T.self, from: unwrapped)
        } catch let error as FetchError {
            throw error
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

        let decision: Bool
        switch error {
        case let .statusCode(code, _):
            decision = policy.retryableStatusCodes.contains(code)
        case let .requestFailed(underlying):
            if let urlError = underlying as? URLError {
                decision = policy.retryableURLErrorCodes.contains(urlError.code)
            } else {
                decision = false
            }
        default:
            decision = false
        }
        if let override = policy.shouldRetry {
            return override(error, attempt)
        }
        return decision
    }

    private func backoffNanoseconds(forAttempt attempt: Int, policy: RetryPolicy) -> UInt64 {
        guard policy.initialBackoff > 0 else { return 0 }
        let exponent = max(Double(attempt - 1), 0)
        let baseSeconds = policy.initialBackoff * pow(policy.backoffMultiplier, exponent)
        let jitterScale = policy.jitterRange.map { Double.random(in: $0) } ?? 1.0
        let seconds = baseSeconds * jitterScale
        return UInt64(seconds * 1_000_000_000)
    }

    private func mergeQueries(
        _ defaults: [String: String],
        _ overrides: [String: String]?
    ) -> [String: String]? {
        guard let overrides else { return defaults.isEmpty ? nil : defaults }
        return defaults.merging(overrides) { _, new in new }
    }

    private func applyInterceptors(to request: URLRequest) async throws -> URLRequest {
        var current = request
        for interceptor in configuration.interceptors {
            current = try await interceptor.adapt(current)
        }
        return current
    }

    private func notifyInterceptors(
        _ result: Result<FetchResponse, FetchError>,
        for request: URLRequest
    ) async {
        for interceptor in configuration.interceptors {
            await interceptor.didReceive(result, for: request)
        }
    }

    private func extractJSON(from data: Data, keyPath: [String]) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        var current: Any = object
        for key in keyPath {
            guard let dict = current as? [String: Any], let next = dict[key] else {
                throw FetchError.missingKeyPath(keyPath)
            }
            current = next
        }

        if JSONSerialization.isValidJSONObject(current) {
            return try JSONSerialization.data(withJSONObject: current)
        }

        switch current {
        case let bool as Bool:
            return (bool ? "true" : "false").data(using: .utf8) ?? Data()
        case let string as String:
            return "\"\(string)\"".data(using: .utf8) ?? Data()
        case let number as NSNumber:
            return number.description.data(using: .utf8) ?? Data()
        case is NSNull:
            return "null".data(using: .utf8) ?? Data()
        default:
            throw FetchError.decodingFailed(underlying: FetchError.missingKeyPath(keyPath))
        }
    }
}


