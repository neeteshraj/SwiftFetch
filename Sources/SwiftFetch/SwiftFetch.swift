import Foundation

/// Minimal namespace for constructing `FetchService` instances.
/// All usage should be instance-first; no globals or shared mutable state remain.
public enum SwiftFetch {
    /// Create a new `FetchService` without any global state.
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
}

