import Foundation

/// Global convenience facade. Prefer creating your own `FetchService` and injecting it.
public enum SwiftFetch {
    private static var sharedService = FetchService()

    /// Configure the shared service with a base URL and optional defaults.
    /// Consider using `FetchService` instances instead of this global for multi-tenant apps.
    public static func configure(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        defaultQuery: [String: String] = [:],
        retryPolicy: FetchClient.RetryPolicy = .init(),
        interceptors: [FetchInterceptor] = [],
        metricsHandler: ((URLRequest, FetchResponse?, FetchError?, TimeInterval) -> Void)? = nil,
        session: URLSession = .shared
    ) {
        sharedService = FetchService(
            baseURL: baseURL,
            defaultHeaders: defaultHeaders,
            defaultQuery: defaultQuery,
            session: session,
            retryPolicy: retryPolicy,
            interceptors: interceptors,
            metricsHandler: metricsHandler
        )
    }

    /// Create a new `FetchService` without mutating the global singleton.
    public static func makeService(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        defaultQuery: [String: String] = [:],
        retryPolicy: FetchClient.RetryPolicy = .init(),
        interceptors: [FetchInterceptor] = [],
        metricsHandler: ((URLRequest, FetchResponse?, FetchError?, TimeInterval) -> Void)? = nil,
        session: URLSession = .shared
    ) -> FetchService {
        FetchService(
            baseURL: baseURL,
            defaultHeaders: defaultHeaders,
            defaultQuery: defaultQuery,
            session: session,
            retryPolicy: retryPolicy,
            interceptors: interceptors,
            metricsHandler: metricsHandler
        )
    }

    /// Perform a GET request and decode the JSON response into the provided type using the shared service.
    public static func getJSON<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await sharedService.getJSON(path, query: query, headers: headers, decoder: decoder)
    }

    /// Perform a POST request with an `Encodable` body and decode a JSON response using the shared service.
    public static func postJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await sharedService.postJSON(path, body: body, query: query, headers: headers, encoder: encoder, decoder: decoder)
    }

    /// Perform a PUT request with an `Encodable` body and decode a JSON response using the shared service.
    public static func putJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await sharedService.putJSON(path, body: body, query: query, headers: headers, encoder: encoder, decoder: decoder)
    }

    /// Access the underlying shared client for advanced scenarios.
    public static var client: FetchClient {
        sharedService.client
    }
}

