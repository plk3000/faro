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
    let message: String

    init(error: any Error) {
        message = (error as? LocalizedError)?.errorDescription
            ?? "FARO vision configuration is invalid."
    }

    func describe(_ image: CapturedImage) async throws -> SceneDescription {
        throw SceneDescriberConfigurationError(message: message)
    }
}

private struct SceneDescriberConfigurationError:
    Error,
    LocalizedError,
    Sendable
{
    let message: String

    var errorDescription: String? { message }
}
