import Foundation

struct SceneDescription: Codable, Equatable, Sendable {
    let text: String
    let language: SupportedLanguage
    let confidence: Double?
    let model: String
    let processingMilliseconds: Int
}

protocol SceneDescribing: Sendable {
    func describe(
        _ image: CapturedImage,
        language: SupportedLanguage
    ) async throws -> SceneDescription
}

enum SceneDescriptionError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding,
    Sendable
{
    case invalidResponse
    case serviceUnavailable
    case timedOut
    case unauthorized

    var appMessage: AppMessage {
        switch self {
        case .invalidResponse:
            AppMessage(.errorVisionInvalidResponse)
        case .serviceUnavailable:
            AppMessage(.errorVisionUnavailable)
        case .timedOut:
            AppMessage(.errorVisionTimeout)
        case .unauthorized:
            AppMessage(.errorVisionUnauthorized)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}
