import Foundation

/// Minimal logging interceptor suitable for debugging or lightweight telemetry.
public struct LoggingInterceptor: FetchInterceptor {
    public enum RedactionStrategy {
        case none
        case redactBodies
    }

    private let log: (String) -> Void
    private let redactedHeaders: Set<String>
    private let bodyRedaction: RedactionStrategy

    public init(
        redactedHeaders: Set<String> = ["Authorization"],
        bodyRedaction: RedactionStrategy = .redactBodies,
        log: @escaping (String) -> Void = { print($0) }
    ) {
        self.redactedHeaders = redactedHeaders
        self.bodyRedaction = bodyRedaction
        self.log = log
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var summary = "[SwiftFetch] → \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<nil>")"
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            let rendered = headers.map { key, value in
                if redactedHeaders.contains(key) {
                    return "\(key): <redacted>"
                }
                return "\(key): \(value)"
            }.joined(separator: ", ")
            summary.append(" [headers: \(rendered)]")
        }
        log(summary)
        return request
    }

    public func didReceive(_ result: Result<FetchResponse, FetchError>, for request: URLRequest) async {
        switch result {
        case .success(let response):
            var line = "[SwiftFetch] ← \(response.statusCode) \(request.url?.absoluteString ?? "<nil>")"
            if !response.data.isEmpty, bodyRedaction == .none {
                line.append(" body=\(String(decoding: response.data, as: UTF8.self))")
            }
            log(line)
        case .failure(let error):
            log("[SwiftFetch] ← error \(error) \(request.url?.absoluteString ?? "<nil>")")
        }
    }
}


