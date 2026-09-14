import Foundation
import Testing
@testable import FARO

@MainActor
final class RecordingSpeechOutput: SpeechOutputProviding {
    private(set) var spoken: [String] = []

    func speak(_ text: String) throws {
        spoken.append(text)
    }

    func stop() {}
}

@MainActor
struct DescribeFlowTests {
    @Test
    func capturesDisplaysAndSpeaksDescription() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let speech = RecordingSpeechOutput()
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(resourceNames: ["kitchen-a"]),
            imageStore: ImageStore(directoryURL: directory),
            sceneDescriber: MockSceneDescriber(
                behavior: .success(
                    text: "A kitchen counter is ahead.",
                    confidence: 0.9
                ),
                delayNanoseconds: 0
            ),
            speechOutput: speech
        )

        await model.describe()

        #expect(model.latestDescription == "A kitchen counter is ahead.")
        #expect(model.storedImages.isEmpty)
        #expect(speech.spoken == ["A kitchen counter is ahead."])
    }
}
