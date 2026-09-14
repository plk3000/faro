import AVFoundation
import Testing
@testable import FARO

struct SpeechOutputConfigurationTests {
    @Test
    func accessibleDefaultIsSlowerThanSystemDefault() {
        let configuration = SpeechOutputConfiguration.accessibleDefault

        #expect(configuration.rate < AVSpeechUtteranceDefaultSpeechRate)
        #expect(configuration.preUtteranceDelay > 0)
        #expect(configuration.phraseDelay >= 0.2)
    }

    @Test
    func insertsAPauseBeforeConjunctionPhrases() {
        let phrases = SpeechPhrasePacer.phrases(
            from: "A chair is ahead and slightly to your left."
        )

        #expect(
            phrases == [
                "A chair is ahead",
                "and slightly to your left."
            ]
        )
        #expect(
            SpeechPhrasePacer.voiceOverText(
                from: "A chair is ahead and slightly to your left."
            ) == "A chair is ahead. And slightly to your left"
        )
    }
}
