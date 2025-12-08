import Foundation

/// Represents an HTTP request definition consumed by `FetchClient`.
public struct FetchRequest {
    public var url: URL
    public var method: HTTPMethod
    public var headers: [String: String]
    public var body: Data?

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

