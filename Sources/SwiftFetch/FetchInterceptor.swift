import Foundation

/// Interceptor hooks to adapt outbound requests and observe results.
/// Implementations are executed in the order provided on the client configuration.
public protocol FetchInterceptor {
    /// Give the interceptor a chance to mutate or replace the outbound URLRequest.
    func adapt(_ request: URLRequest) async throws -> URLRequest

    /// Observe the final result (success or error) for the given request.
    func didReceive(_ result: Result<FetchResponse, FetchError>, for request: URLRequest) async
}

public extension FetchInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest { request }
    func didReceive(_ result: Result<FetchResponse, FetchError>, for request: URLRequest) async {}
}


