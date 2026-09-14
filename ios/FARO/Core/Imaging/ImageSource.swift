import Foundation

protocol ImageSource: Sendable {
    func capture() async throws -> CapturedImage
}

enum ImageSourceError: Error, Equatable, LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case configurationFailed
    case captureInProgress
    case captureFailed
    case fixtureNotFound(String)
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "The camera is unavailable."
        case .permissionDenied:
            "Camera access is not permitted."
        case .configurationFailed:
            "The camera could not be configured."
        case .captureInProgress:
            "An image capture is already in progress."
        case .captureFailed:
            "The camera could not capture an image."
        case let .fixtureNotFound(name):
            "The fixture image \(name) could not be found."
        case .invalidImageData:
            "The captured image could not be read."
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
}
