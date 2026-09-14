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
}
