# Changelog

## 1.0.2
### Added
- Interceptor pipeline (`FetchInterceptor`) with built-in `LoggingInterceptor` for lightweight request/response logs and optional body/header redaction.
- Metrics hook (`metricsHandler`) to capture duration + outcome per request without adding a logging dependency.
- Retry enhancements: optional jitter (`jitterRange`) and a `shouldRetry` override for per-error decisions.
- Per-request controls: timeout, cache policy, explicit `Content-Length`, and body streaming (`bodyStream`) to avoid buffering large payloads.
- Default query merging on configuration to reduce repeated params (e.g., locale, api-version).
- JSON helpers: `postJSON`/`putJSON` for `Encodable` bodies; transformer and key-path decoding helpers for envelope responses.
- Multipart streaming builder to generate an `InputStream` + length for large uploads.
- `MockFetchClient` for unit tests without network calls.

### Changed
- `FetchError` now includes `encodingFailed` and `missingKeyPath` for clearer failure reporting.


