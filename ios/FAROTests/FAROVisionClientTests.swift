import Foundation
import Testing
@testable import FARO

@Suite(.serialized)
struct FAROVisionClientTests {
    @Test
    func sendsMultipartRequestAndDecodesDescription() async throws {
        let session = makeSession { request in
            #expect(request.httpMethod == "POST")
            #expect(
                request.value(forHTTPHeaderField: "Authorization")
                    == "Bearer test-token"
            )
            #expect(
                request.value(forHTTPHeaderField: "Content-Type")?
                    .hasPrefix("multipart/form-data; boundary=") == true
            )

            let requestID = try requestID(from: request)
            let response = """
            {
              "request_id": "\(requestID.uuidString)",
              "description": "A chair is directly ahead.",
              "confidence": 0.91,
              "model": "test/model",
              "processing_ms": 25
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(response.utf8)
            )
        }
        let client = FAROVisionClient(
            baseURL: URL(string: "https://vision.example")!,
            token: "test-token",
            session: session,
            maximumAttempts: 1
        )

        let description = try await client.describe(sampleImage)

        #expect(description.text == "A chair is directly ahead.")
        #expect(description.confidence == 0.91)
        #expect(description.processingMilliseconds == 25)
    }

    @Test
    func retriesAServiceUnavailableResponse() async throws {
        let attempts = LockedCounter()
        let session = makeSession { request in
            let attempt = attempts.increment()
            if attempt == 1 {
                let error = """
                {"error":{"code":"model_unavailable","message":"down","retryable":true}}
                """
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(error.utf8)
                )
            }

            let requestID = try requestID(from: request)
            let response = """
            {
              "request_id": "\(requestID.uuidString)",
              "description": "A clear path is ahead.",
              "confidence": null,
              "model": "test/model",
              "processing_ms": 12
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(response.utf8)
            )
        }
        let client = FAROVisionClient(
            baseURL: URL(string: "https://vision.example")!,
            token: "test-token",
            session: session,
            maximumAttempts: 2
        )

        let description = try await client.describe(sampleImage)

        #expect(description.text == "A clear path is ahead.")
        #expect(attempts.value == 2)
    }

    @Test
    func doesNotRetryUnauthorizedRequests() async {
        let attempts = LockedCounter()
        let session = makeSession { request in
            _ = attempts.increment()
            let error = """
            {"error":{"code":"unauthorized","message":"no","retryable":false}}
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(error.utf8)
            )
        }
        let client = FAROVisionClient(
            baseURL: URL(string: "https://vision.example")!,
            token: "bad-token",
            session: session
        )

        do {
            _ = try await client.describe(sampleImage)
            Issue.record("Expected unauthorized")
        } catch {
            #expect(error as? FAROVisionClientError == .unauthorized)
            #expect(attempts.value == 1)
        }
    }

    private var sampleImage: CapturedImage {
        CapturedImage(data: Data([0xFF, 0xD8]), format: .jpeg)
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws
            -> (HTTPURLResponse, Data)
    ) -> URLSession {
        URLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func requestID(from request: URLRequest) throws -> UUID {
        guard let value = request.value(
            forHTTPHeaderField: "X-Request-ID"
        ),
        let uuid = UUID(uuidString: value) else {
            throw FAROVisionClientError.invalidResponse
        }
        return uuid
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: FAROVisionClientError.invalidResponse
            )
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() -> Int {
        lock.withLock {
            storage += 1
            return storage
        }
    }
}
