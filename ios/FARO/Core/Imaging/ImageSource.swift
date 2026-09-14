import Foundation

protocol ImageSource: Sendable {
    func capture() async throws -> CapturedImage
}

enum ImageSourceError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case cameraUnavailable
    case permissionDenied
    case configurationFailed
    case captureInProgress
    case captureFailed
    case fixtureNotFound(String)
    case invalidImageData

    var appMessage: AppMessage {
        switch self {
        case .cameraUnavailable:
            AppMessage(.errorCameraUnavailable)
        case .permissionDenied:
            AppMessage(.errorCameraPermission)
        case .configurationFailed:
            AppMessage(.errorCameraConfiguration)
        case .captureInProgress:
            AppMessage(.errorCaptureInProgress)
        case .captureFailed:
            AppMessage(.errorCaptureFailed)
        case let .fixtureNotFound(name):
            AppMessage(.errorFixtureNotFound, argument: name)
        case .invalidImageData:
            AppMessage(.errorInvalidImageData)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}

enum ImageSourceFactory {
    static func makeDefault() -> any ImageSource {
#if targetEnvironment(simulator)
        FixtureImageSource()
#else
        CameraImageSource()
#endif
    }
}
