import Foundation

/// Instance-oriented facade over `FetchClient` for dependency injection.
/// Prefer creating and injecting `FetchService` instead of using the global `SwiftFetch`.
public struct FetchService {
    public var client: FetchClient

    public init(client: FetchClient) {
        self.client = client
    }

    public init(
        baseURL: URL? = nil,
        defaultHeaders: [String: String] = [:],
        defaultQuery: [String: String] = [:],
        session: URLSession = .shared,
        retryPolicy: FetchClient.RetryPolicy = .init(),
        interceptors: [FetchInterceptor] = [],
        metricsHandler: ((URLRequest, FetchResponse?, FetchError?, TimeInterval) -> Void)? = nil
    ) {
        self.client = FetchClient(
            configuration: .init(
                baseURL: baseURL,
                defaultHeaders: defaultHeaders,
                defaultQuery: defaultQuery,
                session: session,
                retryPolicy: retryPolicy,
                interceptors: interceptors,
                metricsHandler: metricsHandler
            )
        )
    }

    /// Perform a GET request and decode the JSON response into the provided type.
    public func getJSON<T: Decodable>(
        _ path: String,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let request = FetchRequest(url: try makeURL(from: path), method: .get, headers: headers, body: nil)
        let response = try await client.perform(request, query: query)
        return try client.decodeJSON(T.self, from: response, decoder: decoder)
    }

    /// Perform a POST request with an `Encodable` body and decode a JSON response.
    public func postJSON<Body: Encodable, T: Decodable>(
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
    public func putJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        query: [String: String]? = nil,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await sendJSON(path, method: .put, body: body, query: query, headers: headers, encoder: encoder, decoder: decoder)
    }

    private func sendJSON<Body: Encodable, T: Decodable>(
        _ path: String,
        method: HTTPMethod,
        body: Body,
        query: [String: String]? = nil,
        headers: [String: String],
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) async throws -> T {
        let url = try makeURL(from: path)
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
            let response = try await client.perform(request, query: query)
            return try client.decodeJSON(T.self, from: response, decoder: decoder)
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.encodingFailed(underlying: error)
        }
    }

    private func makeURL(from path: String) throws -> URL {
        guard let url = URL(string: path) else {
            throw FetchError.invalidURL
        }
        return url
    }
}


