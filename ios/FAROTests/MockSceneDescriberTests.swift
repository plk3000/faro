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

        let result = try await describer.describe(image)

        #expect(result.text == "A doorway is ahead.")
        #expect(result.confidence == 0.8)
    }

    @Test
    func defaultDescriptionIsSpanish() async throws {
        let describer = MockSceneDescriber(delayNanoseconds: 0)

        let result = try await describer.describe(image)

        #expect(
            result.text
                == "Hay una silla delante de ti y un poco hacia la izquierda."
        )
    }

    @Test
    func exposesConfiguredFailure() async {
        let describer = MockSceneDescriber(
            behavior: .failure(.serviceUnavailable),
            delayNanoseconds: 0
        )

        do {
            _ = try await describer.describe(image)
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
            _ = try await describer.describe(image)
            Issue.record("Expected timedOut")
        } catch {
            #expect(error as? SceneDescriptionError == .timedOut)
        }
    }
}
