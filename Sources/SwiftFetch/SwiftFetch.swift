import Foundation

/// Global facade for performing HTTP requests through a shared `FetchClient`.
public enum SwiftFetch {
    private static var sharedClient = FetchClient(configuration: .init())

    /// Configure the shared client with a base URL and optional default headers.
    /// - Parameters:
    ///   - baseURL: The base endpoint used for relative request paths.
    ///   - defaultHeaders: Headers merged into every request unless overridden.
    public static func configure(baseURL: URL, defaultHeaders: [String: String] = [:]) {
        sharedClient = FetchClient(
            configuration: .init(baseURL: baseURL, defaultHeaders: defaultHeaders)
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

    /// Access the underlying shared client for advanced scenarios.
    public static var client: FetchClient {
        sharedClient
    }
}

