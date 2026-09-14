@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CaptureViewModel {
    private let imageSource: any ImageSource
    private let imageStore: ImageStore
    private let feedback: any CaptureFeedbackProviding
    private let cameraSource: CameraImageSource?

    private(set) var latestImageData: Data?
    private(set) var storedImages: [StoredImage] = []
    private(set) var isCapturing = false
    private(set) var statusMessage = "Ready to capture"
    private(set) var errorMessage: String?

    var cameraSession: AVCaptureSession? {
        cameraSource?.session
    }

    init(
        imageSource: (any ImageSource)? = nil,
        imageStore: ImageStore = ImageStore(),
        feedback: (any CaptureFeedbackProviding)? = nil
    ) {
        if let imageSource {
            self.imageSource = imageSource
            cameraSource = imageSource as? CameraImageSource
        } else {
#if targetEnvironment(simulator)
            let source = FixtureImageSource()
            self.imageSource = source
            cameraSource = nil
#else
            let source = CameraImageSource()
            self.imageSource = source
            cameraSource = source
#endif
        }
        self.imageStore = imageStore
        self.feedback = feedback ?? CaptureFeedback()
    }

    func prepare() async {
        do {
            if let cameraSource {
                try await cameraSource.prepare()
            }
            storedImages = try await imageStore.list()
            statusMessage = "Ready to capture"
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    func capture() async {
        guard !isCapturing else {
            return
        }

        isCapturing = true
        statusMessage = "Capturing image"
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let image = try await imageSource.capture()
            let storedImage = try await imageStore.save(image)
            latestImageData = try await imageStore.load(storedImage)
            storedImages = try await imageStore.list()
            statusMessage = "Image captured and saved"
            feedback.announceSuccess()
        } catch {
            report(error)
        }
    }

    private func report(_ error: any Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "FARO could not capture an image."
        statusMessage = message
        errorMessage = message
        feedback.announceFailure(message)
    }
}
