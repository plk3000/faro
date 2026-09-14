import Foundation
import Testing
@testable import FARO

@MainActor
private final class RecordingCaptureFeedback: CaptureFeedbackProviding {
    private(set) var successCount = 0
    private(set) var failures: [String] = []
    private(set) var languages: [SupportedLanguage] = []

    func announceSuccess(language: SupportedLanguage) {
        successCount += 1
        languages.append(language)
    }

    func announceFailure(
        _ message: String,
        language: SupportedLanguage
    ) {
        failures.append(message)
        languages.append(language)
    }
}

private struct FailingImageSource: ImageSource {
    let error: ImageSourceError

    func capture() async throws -> CapturedImage {
        throw error
    }
}

@MainActor
struct CaptureViewModelTests {
    @Test
    func capturePersistsAndConfirmsImage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let feedback = RecordingCaptureFeedback()
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(resourceNames: ["kitchen-a"]),
            imageStore: ImageStore(directoryURL: directory),
            feedback: feedback
        )

        await model.capture(language: .englishUS)

        #expect(model.latestImageData != nil)
        #expect(model.storedImages.count == 1)
        #expect(model.errorMessage == nil)
        #expect(feedback.successCount == 1)
        #expect(feedback.failures.isEmpty)
        #expect(feedback.languages == [.englishUS])
    }

    @Test(arguments: SupportedLanguage.allCases)
    func captureErrorsUseTheSelectedLanguage(
        language: SupportedLanguage
    ) async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let feedback = RecordingCaptureFeedback()
        let model = CaptureViewModel(
            imageSource: FailingImageSource(error: .permissionDenied),
            imageStore: ImageStore(directoryURL: directory),
            feedback: feedback
        )

        await model.capture(language: language)

        let expected = ImageSourceError.permissionDenied.appMessage
            .localized(in: language)
        #expect(model.statusText(language: language) == expected)
        #expect(feedback.failures == [expected])
        #expect(feedback.languages == [language])
    }
}
