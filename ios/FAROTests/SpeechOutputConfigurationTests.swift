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
        #expect(configuration.languageCode == "es-MX")
    }

    @Test
    func insertsAPauseBeforeConjunctionPhrases() {
        let phrases = SpeechPhrasePacer.phrases(
            from: "Hay una silla delante de ti y un poco hacia la izquierda."
        )

        #expect(
            phrases == [
                "Hay una silla delante de ti",
                "y un poco hacia la izquierda."
            ]
        )
        #expect(
            SpeechPhrasePacer.voiceOverText(
                from: "Hay una silla delante de ti y un poco hacia la izquierda."
            ) == "Hay una silla delante de ti. Y un poco hacia la izquierda"
        )
    }
}
