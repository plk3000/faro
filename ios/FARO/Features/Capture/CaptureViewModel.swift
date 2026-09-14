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
    private(set) var latestDescription: SceneDescription?
    private(set) var storedImages: [StoredImage] = []
    private(set) var isCapturing = false
    private(set) var isDescribing = false
    private(set) var statusMessage = AppMessage(.statusReady)
    private(set) var errorMessage: AppMessage?

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

    func prepare(language: SupportedLanguage) async {
        do {
            if let cameraSource {
                try await cameraSource.prepare()
            }
            storedImages = try await imageStore.list()
            statusMessage = AppMessage(.statusReady)
            errorMessage = nil
        } catch {
            report(error, language: language)
        }
    }

    func capture(language: SupportedLanguage) async {
        guard !isCapturing, !isDescribing else {
            return
        }

        isCapturing = true
        statusMessage = AppMessage(.statusCapturingImage)
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let image = try await imageSource.capture()
            let storedImage = try await imageStore.save(image)
            latestImageData = try await imageStore.load(storedImage)
            storedImages = try await imageStore.list()
            statusMessage = AppMessage(.statusImageCapturedSaved)
            feedback.announceSuccess(language: language)
        } catch {
            report(error, language: language)
        }
    }

    func describe(language: SupportedLanguage) async {
        guard !isDescribing, !isCapturing else {
            return
        }

        isDescribing = true
        statusMessage = AppMessage(.statusCapturingScene)
        errorMessage = nil
        latestDescription = nil
        defer { isDescribing = false }

        do {
            let image = try await imageSource.capture()
            latestImageData = image.data
            statusMessage = AppMessage(.statusDescribingScene)

            let description = try await sceneDescriber.describe(
                image,
                language: language
            )
            latestDescription = description
            statusMessage = AppMessage(.statusDescriptionReady)
            try speechOutput.speak(
                description.text,
                language: description.language
            )
        } catch {
            report(error, language: language, speak: true)
        }
    }

    func statusText(language: SupportedLanguage) -> String {
        statusMessage.localized(in: language)
    }

    func errorText(language: SupportedLanguage) -> String? {
        errorMessage?.localized(in: language)
    }

    private func report(
        _ error: any Error,
        language: SupportedLanguage,
        speak: Bool = false
    ) {
        let message = AppErrorMessage.message(
            for: error,
            language: language
        )
        statusMessage = message
        errorMessage = message
        let localizedMessage = message.localized(in: language)

        if speak {
            do {
                try speechOutput.speak(
                    localizedMessage,
                    language: language
                )
            } catch {
                feedback.announceFailure(
                    localizedMessage,
                    language: language
                )
            }
        } else {
            feedback.announceFailure(
                localizedMessage,
                language: language
            )
        }
    }
}
