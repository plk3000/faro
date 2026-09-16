import Testing
@testable import FARO

struct WakePhraseMatcherTests {
    private let matcher = WakePhraseMatcher()

    @Test(arguments: [
        ("Hey FARO", SupportedLanguage.englishUS),
        ("Hey, Pharaoh!", SupportedLanguage.englishUS),
        ("Hola FARO", SupportedLanguage.spanishMexico),
        ("Ey faro", SupportedLanguage.spanishMexico),
        ("Ruido antes, hola FARO.", SupportedLanguage.englishUS)
    ])
    func recognizesBilingualWakePhrases(
        transcript: String,
        language: SupportedLanguage
    ) {
        #expect(matcher.matches(transcript, language: language))
    }

    @Test(arguments: [
        "",
        "FARO",
        "hello",
        "the lighthouse is ahead",
        "hola amigo"
    ])
    func rejectsIncompleteAndUnrelatedSpeech(_ transcript: String) {
        #expect(
            !matcher.matches(
                transcript,
                language: .englishUS
            )
        )
    }

    @Test(arguments: SupportedLanguage.allCases)
    func suppliesBothPhrasesAsRecognitionContext(
        language: SupportedLanguage
    ) {
        #expect(
            language.wakePhraseContextualStrings == [
                "Hey FARO",
                "Hola FARO"
            ]
        )
    }

    @Test
    func detectsASplitPhraseOnlyOncePerSession() {
        var accumulator = WakePhraseTranscriptAccumulator()

        let firstFragment = accumulator.observe(
            "Hey",
            language: .englishUS
        )
        let secondFragment = accumulator.observe(
            "FARO",
            language: .englishUS
        )
        let duplicateFragment = accumulator.observe(
            "Hey FARO",
            language: .englishUS
        )

        #expect(!firstFragment)
        #expect(secondFragment)
        #expect(!duplicateFragment)
        #expect(accumulator.hasDetectedWakePhrase)
    }
}
