import Foundation

/// The raw response payload and metadata returned by `FetchClient`.
public struct FetchResponse {
    public let data: Data
    public let response: HTTPURLResponse

    /// Convenience accessor for `HTTPURLResponse.statusCode`.
    public var statusCode: Int {
        response.statusCode
    }
}

