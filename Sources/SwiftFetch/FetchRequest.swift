import Foundation

/// Represents an HTTP request definition consumed by `FetchClient`.
public struct FetchRequest {
    public var url: URL
    public var method: HTTPMethod
    public var headers: [String: String]
    /// Eager request body payload.
    public var body: Data?
    /// Streaming request body. Ignored when `body` is provided.
    public var bodyStream: InputStream?
    /// Optional explicit content length to set on the request.
    public var contentLength: Int64?
    /// Optional timeout override applied to the `URLRequest`.
    public var timeoutInterval: TimeInterval?
    /// Optional cache policy override applied to the `URLRequest`.
    public var cachePolicy: URLRequest.CachePolicy?

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        bodyStream: InputStream? = nil,
        contentLength: Int64? = nil,
        timeoutInterval: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.bodyStream = bodyStream
        self.contentLength = contentLength
        self.timeoutInterval = timeoutInterval
        self.cachePolicy = cachePolicy
    }
}

