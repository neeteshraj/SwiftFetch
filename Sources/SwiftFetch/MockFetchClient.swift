import Foundation

/// Simple test double that mimics `FetchClient` without hitting the network.
public final class MockFetchClient {
    public private(set) var performedRequests: [FetchRequest] = []
    private var queuedResults: [Result<FetchResponse, FetchError>] = []

    public init() {}

    /// Queue a result that will be returned on the next `perform` call.
    public func enqueue(_ result: Result<FetchResponse, FetchError>) {
        queuedResults.append(result)
    }

    /// Clears recorded requests and queued results.
    public func reset() {
        performedRequests.removeAll()
        queuedResults.removeAll()
    }

    public func perform(
        _ request: FetchRequest,
        query: [String: String]? = nil
    ) async throws -> FetchResponse {
        performedRequests.append(request)
        guard !queuedResults.isEmpty else {
            throw FetchError.requestFailed(underlying: NSError(domain: "MockFetchClient", code: -1))
        }
        let result = queuedResults.removeFirst()
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    public func decodeJSON<T: Decodable>(
        _ type: T.Type,
        from response: FetchResponse,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        return try FetchClient(configuration: .init()).decodeJSON(type, from: response, decoder: decoder)
    }
}


