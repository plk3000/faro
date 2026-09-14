import Foundation
import Testing
@testable import FARO

@MainActor
private final class RecordingCaptureFeedback: CaptureFeedbackProviding {
    private(set) var successCount = 0
    private(set) var failures: [String] = []

    func announceSuccess() {
        successCount += 1
    }

    func announceFailure(_ message: String) {
        failures.append(message)
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

        await model.capture()

        #expect(model.latestImageData != nil)
        #expect(model.storedImages.count == 1)
        #expect(model.errorMessage == nil)
        #expect(feedback.successCount == 1)
        #expect(feedback.failures.isEmpty)
    }
}
