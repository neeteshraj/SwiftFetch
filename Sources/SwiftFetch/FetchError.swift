import Foundation

/// Typed errors surfaced by `FetchClient`.
public enum FetchError: Error {
    case invalidURL
    case invalidResponse
    case statusCode(Int, data: Data?)
    case requestFailed(underlying: Error)
    case decodingFailed(underlying: Error)
}

