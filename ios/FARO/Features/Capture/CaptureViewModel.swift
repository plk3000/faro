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
    private let sceneDescriber: any SceneDescribing
    private let speechOutput: any SpeechOutputProviding

    private(set) var latestImageData: Data?
    private(set) var latestDescription: String?
    private(set) var storedImages: [StoredImage] = []
    private(set) var isCapturing = false
    private(set) var isDescribing = false
    private(set) var statusMessage = "Ready to capture"
    private(set) var errorMessage: String?

    var cameraSession: AVCaptureSession? {
        cameraSource?.session
    }

    init(
        imageSource: (any ImageSource)? = nil,
        imageStore: ImageStore = ImageStore(),
        feedback: (any CaptureFeedbackProviding)? = nil,
        sceneDescriber: (any SceneDescribing)? = nil,
        speechOutput: (any SpeechOutputProviding)? = nil
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
        self.sceneDescriber = sceneDescriber
            ?? SceneDescriberFactory.makeDefault()
        self.speechOutput = speechOutput ?? SpeechOutput()
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
        guard !isCapturing, !isDescribing else {
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

    func describe() async {
        guard !isDescribing, !isCapturing else {
            return
        }

        isDescribing = true
        statusMessage = "Capturing a scene to describe"
        errorMessage = nil
        latestDescription = nil
        defer { isDescribing = false }

        do {
            let image = try await imageSource.capture()
            latestImageData = image.data
            statusMessage = "Describing scene"

            let description = try await sceneDescriber.describe(image)
            latestDescription = description.text
            statusMessage = "Description ready"
            try speechOutput.speak(description.text)
        } catch {
            report(error, speak: true)
        }
    }

    private func report(_ error: any Error, speak: Bool = false) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? "FARO could not complete that action."
        statusMessage = message
        errorMessage = message

        if speak {
            do {
                try speechOutput.speak(message)
            } catch {
                feedback.announceFailure(message)
            }
        } else {
            feedback.announceFailure(message)
        }
    }
}
