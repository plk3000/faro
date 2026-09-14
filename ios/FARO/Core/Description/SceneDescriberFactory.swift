import Foundation

enum SceneDescriberFactory {
    static func makeDefault(
        bundle: Bundle = .main
    ) -> any SceneDescribing {
        do {
            let configuration = try AppConfiguration.load(from: bundle)
            switch configuration.visionMode {
            case .mock:
                return MockSceneDescriber()
            case .live:
                guard let baseURL = configuration.visionBaseURL,
                      let token = configuration.visionToken else {
                    return FailingSceneDescriber(
                        error: AppConfigurationError.missingVisionToken
                    )
                }
                return FAROVisionClient(
                    baseURL: baseURL,
                    token: token
                )
            }
        } catch {
            return FailingSceneDescriber(error: error)
        }
    }
}

private struct FailingSceneDescriber: SceneDescribing {
    let appMessage: AppMessage

    init(error: any Error) {
        appMessage = (error as? any AppMessageProviding)?.appMessage
            ?? AppMessage(.errorVisionConfiguration)
    }

    func describe(
        _ image: CapturedImage,
        language: SupportedLanguage
    ) async throws -> SceneDescription {
        throw SceneDescriberConfigurationError(appMessage: appMessage)
    }
}

private struct SceneDescriberConfigurationError:
    Error,
    LocalizedError,
    Sendable
{
    let appMessage: AppMessage

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}

extension SceneDescriberConfigurationError: AppMessageProviding {}
