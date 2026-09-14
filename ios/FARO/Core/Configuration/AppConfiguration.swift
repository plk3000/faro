import Foundation

struct AppConfiguration: Equatable, Sendable {
    enum VisionMode: String, Sendable {
        case mock
        case live
    }

    let visionMode: VisionMode
    let visionBaseURL: URL?
    let visionToken: String?

    static func load(from bundle: Bundle = .main) throws -> AppConfiguration {
        let modeValue = bundle.object(
            forInfoDictionaryKey: "FAROVisionMode"
        ) as? String ?? "mock"
        guard let visionMode = VisionMode(rawValue: modeValue) else {
            throw AppConfigurationError.invalidVisionMode(modeValue)
        }

        let urlValue = bundle.object(
            forInfoDictionaryKey: "FAROVisionBaseURL"
        ) as? String
        let tokenValue = bundle.object(
            forInfoDictionaryKey: "FAROVisionToken"
        ) as? String

        let baseURL = urlValue
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let token = tokenValue.flatMap { $0.isEmpty ? nil : $0 }

        if visionMode == .live {
            guard let baseURL,
                  baseURL.scheme == "https" || isLocalDevelopment(baseURL) else {
                throw AppConfigurationError.invalidVisionBaseURL
            }
            guard token != nil else {
                throw AppConfigurationError.missingVisionToken
            }
        }

        return AppConfiguration(
            visionMode: visionMode,
            visionBaseURL: baseURL,
            visionToken: token
        )
    }

    private static func isLocalDevelopment(_ url: URL) -> Bool {
        guard url.scheme == "http" else {
            return false
        }
        return url.host == "localhost" || url.host == "127.0.0.1"
    }
}

enum AppConfigurationError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case invalidVisionMode(String)
    case invalidVisionBaseURL
    case missingVisionToken

    var appMessage: AppMessage {
        switch self {
        case let .invalidVisionMode(value):
            AppMessage(.errorInvalidVisionMode, argument: value)
        case .invalidVisionBaseURL:
            AppMessage(.errorInvalidVisionURL)
        case .missingVisionToken:
            AppMessage(.errorMissingVisionToken)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}
