import Foundation

/// Global facade for performing HTTP requests through a shared `FetchClient`.
public enum SwiftFetch {
    private static var sharedClient = FetchClient(configuration: .init())

    /// Configure the shared client with a base URL and optional default headers.
    /// - Parameters:
    ///   - baseURL: The base endpoint used for relative request paths.
    ///   - defaultHeaders: Headers merged into every request unless overridden.
    ///   - retryPolicy: Optional retry behavior; disabled by default.
    public static func configure(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        defaultQuery: [String: String] = [:],
        retryPolicy: FetchClient.RetryPolicy = .init(),
        interceptors: [FetchInterceptor] = [],
        metricsHandler: ((URLRequest, FetchResponse?, FetchError?, TimeInterval) -> Void)? = nil
    ) {
        sharedClient = FetchClient(
            configuration: .init(
                baseURL: baseURL,
                defaultHeaders: defaultHeaders,
                defaultQuery: defaultQuery,
                retryPolicy: retryPolicy,
                interceptors: interceptors,
                metricsHandler: metricsHandler
            )
        )
    }

    /// Perform a GET request and decode the JSON response into the provided type.
    /// - Parameters:
    ///   - path: Absolute URL or a path relative to the configured base URL.
    ///   - query: Optional query parameters appended to the request.
    ///   - headers: Request-specific headers merged over defaults.
    ///   - decoder: Custom JSON decoder if special strategies are needed.
    /// - Returns: A decoded instance of `T`.
    public static func getJSON<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let url = URL(string: path) ?? URL(fileURLWithPath: path)
        let request = FetchRequest(url: url, method: .get, headers: headers, body: nil)
        let response = try await sharedClient.perform(request, query: query)
        return try sharedClient.decodeJSON(T.self, from: response, decoder: decoder)
    }

    /// Perform a POST request with an `Encodable` body and decode a JSON response.
    public static func postJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await sendJSON(path, method: .post, body: body, query: query, headers: headers, encoder: encoder, decoder: decoder)
    }

    /// Perform a PUT request with an `Encodable` body and decode a JSON response.
    public static func putJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await sendJSON(path, method: .put, body: body, query: query, headers: headers, encoder: encoder, decoder: decoder)
    }

    private static func sendJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        method: HTTPMethod,
        body: Body,
        query: [String: String]? = nil,
        headers: [String: String],
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) async throws -> T {
        let url = URL(string: path) ?? URL(fileURLWithPath: path)
        do {
            let payload = try encoder.encode(body)
            var mergedHeaders = headers
            if mergedHeaders["Content-Type"] == nil {
                mergedHeaders["Content-Type"] = "application/json"
            }
            let request = FetchRequest(
                url: url,
                method: method,
                headers: mergedHeaders,
                body: payload
            )
            let response = try await sharedClient.perform(request, query: query)
            return try sharedClient.decodeJSON(T.self, from: response, decoder: decoder)
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.encodingFailed(underlying: error)
        }
    }

    /// Access the underlying shared client for advanced scenarios.
    public static var client: FetchClient {
        sharedClient
    }
}

