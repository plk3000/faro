import Foundation
import Testing
@testable import FARO

@MainActor
final class RecordingSpeechOutput: SpeechOutputProviding {
    struct Entry: Equatable {
        let text: String
        let language: SupportedLanguage
    }

    private(set) var spoken: [Entry] = []
    private(set) var stopCount = 0

    func speak(
        _ text: String,
        language: SupportedLanguage
    ) throws {
        spoken.append(Entry(text: text, language: language))
    }

    func stop() {
        stopCount += 1
    }
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

        await model.describe(language: .englishUS)

        #expect(model.latestDescription?.text == "A kitchen counter is ahead.")
        #expect(model.latestDescription?.language == .englishUS)
        #expect(model.storedImages.isEmpty)
        #expect(
            speech.spoken == [
                .init(
                    text: "A kitchen counter is ahead.",
                    language: .englishUS
                )
            ]
        )
    }

    @Test
    func changingLanguageAffectsTheNextDescriptionWithoutRelaunch() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let speech = RecordingSpeechOutput()
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a", "kitchen-b"]
            ),
            imageStore: ImageStore(directoryURL: directory),
            sceneDescriber: MockSceneDescriber(delayNanoseconds: 0),
            speechOutput: speech
        )

        await model.describe(language: .englishUS)
        await model.describe(language: .spanishMexico)

        #expect(speech.spoken.count == 2)
        #expect(speech.spoken[0].language == .englishUS)
        #expect(
            speech.spoken[0].text
                == SupportedLanguage.englishUS.mockDescription
        )
        #expect(speech.spoken[1].language == .spanishMexico)
        #expect(
            speech.spoken[1].text
                == SupportedLanguage.spanishMexico.mockDescription
        )
    }
}
