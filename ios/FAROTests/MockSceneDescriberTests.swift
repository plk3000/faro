import Foundation
import Testing
@testable import FARO

struct MockSceneDescriberTests {
    private let image = CapturedImage(
        data: Data([0x01]),
        format: .jpeg
    )

    @Test
    func returnsConfiguredDescription() async throws {
        let describer = MockSceneDescriber(
            behavior: .success(text: "A doorway is ahead.", confidence: 0.8),
            delayNanoseconds: 0
        )

        let result = try await describer.describe(
            image,
            language: .englishUS
        )

        #expect(result.text == "A doorway is ahead.")
        #expect(result.language == .englishUS)
        #expect(result.confidence == 0.8)
    }

    @Test(arguments: SupportedLanguage.allCases)
    func defaultDescriptionMatchesRequestedLanguage(
        language: SupportedLanguage
    ) async throws {
        let describer = MockSceneDescriber(delayNanoseconds: 0)

        let result = try await describer.describe(
            image,
            language: language
        )

        #expect(result.text == language.mockDescription)
        #expect(result.language == language)
    }

    @Test
    func exposesConfiguredFailure() async {
        let describer = MockSceneDescriber(
            behavior: .failure(.serviceUnavailable),
            delayNanoseconds: 0
        )

        do {
            _ = try await describer.describe(
                image,
                language: .englishUS
            )
            Issue.record("Expected serviceUnavailable")
        } catch {
            #expect(error as? SceneDescriptionError == .serviceUnavailable)
        }
    }

    @Test
    func exposesTimeout() async {
        let describer = MockSceneDescriber(
            behavior: .timeout,
            delayNanoseconds: 0
        )

        do {
            _ = try await describer.describe(
                image,
                language: .spanishMexico
            )
            Issue.record("Expected timedOut")
        } catch {
            #expect(error as? SceneDescriptionError == .timedOut)
        }
    }
}
