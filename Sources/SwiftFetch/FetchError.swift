import Foundation

/// Typed errors surfaced by `FetchClient`.
public enum FetchError: Error {
    /// The request URL could not be formed (e.g., missing base URL for a relative path).
    case invalidURL
    /// A response was received but was not an `HTTPURLResponse`.
    case invalidResponse
    /// The server returned a non-2xx status code. The raw body (if any) is included for debugging.
    case statusCode(Int, data: Data?)
    /// The underlying transport or session failed before a response was produced.
    case requestFailed(underlying: Error)
    /// Encoding the outbound payload failed.
    case encodingFailed(underlying: Error)
    /// JSON decoding failed for the expected response type.
    case decodingFailed(underlying: Error)
    /// A nested JSON key path could not be resolved.
    case missingKeyPath([String])
}

