import Foundation

struct FAROVisionClient: SceneDescribing {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let timeout: TimeInterval
    private let maximumAttempts: Int

    init(
        baseURL: URL,
        token: String,
        session: URLSession = .shared,
        timeout: TimeInterval = 20,
        maximumAttempts: Int = 2
    ) {
        precondition(maximumAttempts > 0)
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.timeout = timeout
        self.maximumAttempts = maximumAttempts
    }

    func describe(_ image: CapturedImage) async throws -> SceneDescription {
        let requestID = UUID()
        var lastError: (any Error)?

        for attempt in 1...maximumAttempts {
            try Task.checkCancellation()

            do {
                return try await performRequest(
                    image: image,
                    requestID: requestID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as FAROVisionClientError {
                lastError = error
                guard error.isRetryable, attempt < maximumAttempts else {
                    throw error
                }
            } catch let error as URLError {
                let mapped = FAROVisionClientError.network(error.code)
                lastError = mapped
                guard mapped.isRetryable, attempt < maximumAttempts else {
                    throw mapped
                }
            }

            try await Task.sleep(for: .milliseconds(250 * attempt))
        }

        throw lastError ?? FAROVisionClientError.invalidResponse
    }

    private func performRequest(
        image: CapturedImage,
        requestID: UUID
    ) async throws -> SceneDescription {
        let boundary = "FARO-\(UUID().uuidString)"
        var request = URLRequest(
            url: baseURL.appendingPathComponent(
                "v1/scene-descriptions"
            )
        )
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            requestID.uuidString,
            forHTTPHeaderField: "X-Request-ID"
        )
        request.httpBody = try multipartBody(
            image: image,
            requestID: requestID,
            boundary: boundary
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FAROVisionClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw parseError(
                statusCode: httpResponse.statusCode,
                data: data
            )
        }

        let payload: SuccessPayload
        do {
            payload = try JSONDecoder().decode(
                SuccessPayload.self,
                from: data
            )
        } catch {
            throw FAROVisionClientError.invalidResponse
        }

        guard payload.requestID == requestID,
              !payload.description.isEmpty else {
            throw FAROVisionClientError.invalidResponse
        }

        return SceneDescription(
            text: payload.description,
            confidence: payload.confidence,
            model: payload.model,
            processingMilliseconds: payload.processingMilliseconds
        )
    }

    private func multipartBody(
        image: CapturedImage,
        requestID: UUID,
        boundary: String
    ) throws -> Data {
        let options = RequestOptions(
            requestID: requestID,
            locale: Locale.current.identifier,
            detail: "brief",
            prompt: "Describe nearby objects, their relative position, and immediate obstacles."
        )
        let optionsData = try JSONEncoder().encode(options)

        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"image\"; filename=\"scene.\(image.format.rawValue)\"\r\n"
        )
        body.appendUTF8("Content-Type: \(image.format.mimeType)\r\n\r\n")
        body.append(image.data)
        body.appendUTF8("\r\n--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"options\"\r\n"
        )
        body.appendUTF8("Content-Type: application/json\r\n\r\n")
        body.append(optionsData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }

    private func parseError(
        statusCode: Int,
        data: Data
    ) -> FAROVisionClientError {
        let payload = try? JSONDecoder().decode(
            ErrorEnvelope.self,
            from: data
        )
        let code = payload?.error.code

        switch (statusCode, code) {
        case (401, _):
            return .unauthorized
        case (429, _):
            return .rateLimited
        case (503, _):
            return .serviceUnavailable
        case (504, _):
            return .timedOut
        case (400, _), (413, _), (415, _):
            return .rejectedRequest(code ?? "invalid_request")
        default:
            return .server(statusCode)
        }
    }
}

enum FAROVisionClientError: Error, Equatable, LocalizedError {
    case invalidResponse
    case network(URLError.Code)
    case rateLimited
    case rejectedRequest(String)
    case server(Int)
    case serviceUnavailable
    case timedOut
    case unauthorized

    var isRetryable: Bool {
        switch self {
        case .network, .rateLimited, .server, .serviceUnavailable, .timedOut:
            true
        case .invalidResponse, .rejectedRequest, .unauthorized:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The vision service returned an invalid response."
        case .network:
            "FARO could not reach the vision service."
        case .rateLimited:
            "The vision service is busy. Try again shortly."
        case .rejectedRequest:
            "The vision service rejected the image."
        case .server, .serviceUnavailable:
            "Scene description is temporarily unavailable."
        case .timedOut:
            "Scene description took too long."
        case .unauthorized:
            "The vision service rejected the app credentials."
        }
    }
}

private struct RequestOptions: Encodable {
    let requestID: UUID
    let locale: String
    let detail: String
    let prompt: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case locale
        case detail
        case prompt
    }
}

private struct SuccessPayload: Decodable {
    let requestID: UUID
    let description: String
    let confidence: Double?
    let model: String
    let processingMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case description
        case confidence
        case model
        case processingMilliseconds = "processing_ms"
    }
}

private struct ErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
    }

    let error: Payload
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}
