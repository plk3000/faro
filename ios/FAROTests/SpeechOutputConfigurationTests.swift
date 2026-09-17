import AVFoundation
import Dispatch
import Foundation
import Testing
@testable import FARO

@MainActor
private final class SpeechCompletionFlag {
    var value = false
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

struct SpeechOutputConfigurationTests {
    @Test
    func accessibleDefaultIsSlowerThanSystemDefault() {
        let configuration = SpeechOutputConfiguration.accessibleDefault

        #expect(configuration.rate < AVSpeechUtteranceDefaultSpeechRate)
        #expect(configuration.preUtteranceDelay > 0)
        #expect(configuration.phraseDelay >= 0.2)
    }

    @Test(arguments: [
        (
            SupportedLanguage.englishUS,
            "A chair is ahead and slightly to your left.",
            ["A chair is ahead", "and slightly to your left."]
        ),
        (
            SupportedLanguage.spanishMexico,
            "Hay una silla delante de ti y un poco hacia la izquierda.",
            ["Hay una silla delante de ti", "y un poco hacia la izquierda."]
        )
    ])
    func insertsLanguageSpecificPhrasePauses(
        language: SupportedLanguage,
        text: String,
        expected: [String]
    ) {
        let phrases = SpeechPhrasePacer.phrases(
            from: text,
            language: language
        )

        #expect(phrases == expected)
    }

    @Test
    func voiceOverTextUsesSpanishPacing() {
        #expect(
            SpeechPhrasePacer.voiceOverText(
                from: "Hay una silla delante de ti y un poco hacia la izquierda.",
                language: .spanishMexico
            ) == "Hay una silla delante de ti. Y un poco hacia la izquierda"
        )
    }

    @Test(arguments: SupportedLanguage.allCases)
    func missingVoiceErrorIsLocalized(language: SupportedLanguage) {
        let error = SpeechOutputError.voiceUnavailable("test")

        #expect(
            !error.appMessage.localized(in: language).isEmpty
        )
    }

    @Test
    @MainActor
    func waitsForEveryQueuedUtterance() async {
        let first = AVSpeechUtterance(string: "First")
        let second = AVSpeechUtterance(string: "Second")
        let tracker = SpeechUtteranceCompletionTracker()
        let completed = SpeechCompletionFlag()
        tracker.begin([first, second])

        let waitTask = Task { @MainActor in
            await tracker.waitUntilFinished()
            completed.value = true
        }
        await Task.yield()
        #expect(!completed.value)

        tracker.complete(ObjectIdentifier(first))
        await Task.yield()
        #expect(!completed.value)

        tracker.complete(ObjectIdentifier(second))
        await waitTask.value
        #expect(completed.value)
    }

    @Test
    @MainActor
    func delegateCompletionCanArriveOffMainActor() async {
        let output = SpeechOutput()
        let synthesizer = UncheckedSendable(
            value: AVSpeechSynthesizer()
        )
        let utterance = UncheckedSendable(
            value: AVSpeechUtterance(string: "Finished")
        )

        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                output.speechSynthesizer(
                    synthesizer.value,
                    didFinish: utterance.value
                )
                continuation.resume()
            }
        }
        await Task.yield()
    }
}
