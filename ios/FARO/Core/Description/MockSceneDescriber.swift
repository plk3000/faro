import Foundation

struct MockSceneDescriber: SceneDescribing {
    enum Behavior: Sendable {
        case success(text: String, confidence: Double?)
        case failure(SceneDescriptionError)
        case timeout
    }

    let behavior: Behavior
    let delayNanoseconds: UInt64

    init(
        behavior: Behavior = .success(
            text: "Hay una silla delante de ti y un poco hacia la izquierda.",
            confidence: 0.9
        ),
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        self.behavior = behavior
        self.delayNanoseconds = delayNanoseconds
    }

    func describe(_ image: CapturedImage) async throws -> SceneDescription {
        try await Task<Never, Never>.sleep(nanoseconds: delayNanoseconds)

        switch behavior {
        case let .success(text, confidence):
            return SceneDescription(
                text: text,
                confidence: confidence,
                model: "mock",
                processingMilliseconds: Int(delayNanoseconds / 1_000_000)
            )
        case let .failure(error):
            throw error
        case .timeout:
            throw SceneDescriptionError.timedOut
        }
    }
}
