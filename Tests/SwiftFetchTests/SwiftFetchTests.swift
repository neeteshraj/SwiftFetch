import Foundation
import XCTest
@testable import SwiftFetch

final class SwiftFetchTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com")!

    private func makeClient(
        retryPolicy: FetchClient.RetryPolicy = .init()
    ) -> FetchClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = FetchClient.Configuration(
            baseURL: baseURL,
            defaultHeaders: ["X-Default": "1"],
            session: session,
            retryPolicy: retryPolicy
        )
        return FetchClient(configuration: config)
    }

    func testURLBuilding_appendsBaseAndQuery() async throws {
        let client = makeClient()
        let invoked = expectation(description: "handler invoked")

        MockURLProtocol.requestHandler = { request in
            invoked.fulfill()
            guard let url = request.url else { throw FetchError.invalidURL }
            XCTAssertEqual(
                url.absoluteString,
                "https://api.example.com/users?page=1"
            )

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let request = FetchRequest(url: URL(string: "/users")!)
        _ = try await client.perform(request, query: ["page": "1"])
        await fulfillment(of: [invoked], timeout: 1.0)
    }

    func testJSONDecodingSuccess() async throws {
        struct User: Decodable, Equatable {
            let id: Int
            let name: String
        }

        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let data = """
            {"id":1,"name":"Ada"}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let request = FetchRequest(url: URL(string: "/user")!)
        let response = try await client.perform(request)
        let user = try client.decodeJSON(User.self, from: response)

        XCTAssertEqual(user, User(id: 1, name: "Ada"))
    }

    func testNon200StatusThrowsStatusCode() async {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let data = Data("nope".utf8)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let request = FetchRequest(url: URL(string: "/missing")!)
        do {
            _ = try await client.perform(request)
            XCTFail("Expected status code error")
        } catch let FetchError.statusCode(code, data) {
            XCTAssertEqual(code, 404)
            XCTAssertEqual(String(data: data ?? Data(), encoding: .utf8), "nope")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testDecodingFailureMapsError() async throws {
        struct User: Decodable {
            let id: Int
            let name: String
        }

        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            let url = request.url!
            let data = Data(#"{"id": "abc"}"#.utf8) // missing name and wrong type
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let request = FetchRequest(url: URL(string: "/user")!)
        let response = try await client.perform(request)
        do {
            _ = try client.decodeJSON(User.self, from: response)
            XCTFail("Expected decoding failure")
        } catch FetchError.decodingFailed {
            // expected
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testRetriesWhenEnabledForRetryableStatus() async throws {
        var attempts = 0
        let policy = FetchClient.RetryPolicy(
            isEnabled: true,
            maxRetries: 2,
            initialBackoff: 0,
            backoffMultiplier: 1,
            retryableStatusCodes: [503],
            retryableURLErrorCodes: []
        )
        let client = makeClient(retryPolicy: policy)

        MockURLProtocol.requestHandler = { request in
            attempts += 1
            let url = request.url!
            if attempts < 3 {
                let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (response, Data("down".utf8))
            } else {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("ok".utf8))
            }
        }

        let request = FetchRequest(url: URL(string: "/ping")!)
        let response = try await client.perform(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(attempts, 3, "Should retry twice before succeeding")
    }

    func testDoesNotRetryWhenDisabled() async {
        var attempts = 0
        let policy = FetchClient.RetryPolicy(
            isEnabled: false,
            maxRetries: 3,
            initialBackoff: 0,
            backoffMultiplier: 1,
            retryableStatusCodes: [503],
            retryableURLErrorCodes: []
        )
        let client = makeClient(retryPolicy: policy)

        MockURLProtocol.requestHandler = { request in
            attempts += 1
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("down".utf8))
        }

        let request = FetchRequest(url: URL(string: "/ping")!)
        do {
            _ = try await client.perform(request)
            XCTFail("Expected status code error")
        } catch FetchError.statusCode {
            XCTAssertEqual(attempts, 1, "Should not retry when disabled")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testQueryParametersMergeWithExisting() async throws {
        let client = makeClient()
        let invoked = expectation(description: "handler invoked")

        MockURLProtocol.requestHandler = { request in
            invoked.fulfill()
            guard let url = request.url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = components.queryItems else {
                throw FetchError.invalidURL
            }

            let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
            XCTAssertEqual(dict["existing"], "1")
            XCTAssertEqual(dict["q"], "swift")
            XCTAssertEqual(dict["page"], "2")

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let request = FetchRequest(url: URL(string: "/search?existing=1")!)
        _ = try await client.perform(request, query: ["q": "swift", "page": "2"])
        await fulfillment(of: [invoked], timeout: 1.0)
    }

    func testFetchServiceUsesBaseForRelativePath() async throws {
        struct Empty: Decodable {}
        let client = makeClient()
        let service = FetchService(client: client)
        let invoked = expectation(description: "handler invoked")

        MockURLProtocol.requestHandler = { request in
            invoked.fulfill()
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/users")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let _: Empty = try await service.getJSON("users")
        await fulfillment(of: [invoked], timeout: 1.0)
    }

    func testMultipartBuilderProducesContentTypeAndBoundary() {
        var form = MultipartFormData(boundary: "Boundary-TEST")
        form.addField(name: "name", value: "alice")
        form.addData(
            name: "file",
            filename: "hello.txt",
            mimeType: "text/plain",
            data: Data("hi".utf8)
        )

        let result = form.build()
        XCTAssertTrue(result.contentType.contains("multipart/form-data"))
        XCTAssertTrue(result.contentType.contains("Boundary-TEST"))

        let bodyString = String(data: result.data, encoding: .utf8)!
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"name\""))
        XCTAssertTrue(bodyString.contains("alice"))
        XCTAssertTrue(bodyString.contains("filename=\"hello.txt\""))
        XCTAssertTrue(bodyString.contains("Content-Type: text/plain"))
        XCTAssertTrue(bodyString.contains("hi"))
        XCTAssertTrue(bodyString.contains("--Boundary-TEST--"))
    }
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: FetchError.invalidURL)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}

