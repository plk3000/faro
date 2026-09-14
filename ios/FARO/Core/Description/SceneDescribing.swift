import Foundation

struct SceneDescription: Codable, Equatable, Sendable {
    let text: String
    let confidence: Double?
    let model: String
    let processingMilliseconds: Int
}

protocol SceneDescribing: Sendable {
    func describe(_ image: CapturedImage) async throws -> SceneDescription
}

enum SceneDescriptionError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse
    case serviceUnavailable
    case timedOut
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The vision service returned an invalid response."
        case .serviceUnavailable:
            "Scene description is temporarily unavailable."
        case .timedOut:
            "Scene description took too long."
        case .unauthorized:
            "The vision service rejected the app credentials."
        }
    }
}
