import Testing
@testable import FARO

struct VoiceCommandParserTests {
    private let parser = VoiceCommandParser()

    @Test(arguments: [
        (
            "Describe.",
            SupportedLanguage.englishUS,
            VoiceCommand.describeScene
        ),
        (
            "FARO, please describe the scene.",
            SupportedLanguage.englishUS,
            VoiceCommand.describeScene
        ),
        (
            "¿Dónde estoy?",
            SupportedLanguage.spanishMexico,
            VoiceCommand.whereAmI
        ),
        (
            "Dime dónde estoy, por favor.",
            SupportedLanguage.spanishMexico,
            VoiceCommand.whereAmI
        ),
        (
            "What's ahead?",
            SupportedLanguage.englishUS,
            VoiceCommand.whatIsAhead
        ),
        (
            "¿Qué hay delante?",
            SupportedLanguage.spanishMexico,
            VoiceCommand.whatIsAhead
        ),
        (
            "Remember this as Main Office.",
            SupportedLanguage.englishUS,
            VoiceCommand.rememberPlace(label: "Main Office")
        ),
        (
            "Recuerda este lugar como Cocina de José, por favor.",
            SupportedLanguage.spanishMexico,
            VoiceCommand.rememberPlace(label: "Cocina de José")
        )
    ])
    func parsesBilingualPhrasing(
        transcript: String,
        language: SupportedLanguage,
        expected: VoiceCommand
    ) {
        #expect(
            parser.parse(transcript, language: language) == expected
        )
    }

    @Test(arguments: SupportedLanguage.allCases)
    func rejectsUnknownAndIncompleteCommands(
        language: SupportedLanguage
    ) {
        #expect(
            parser.parse(
                "Turn on the lights",
                language: language
            ) == nil
        )
        let incomplete = language == .englishUS
            ? "Remember this as"
            : "Recuerda este lugar como"
        #expect(
            parser.parse(incomplete, language: language) == nil
        )
    }

    @Test(arguments: SupportedLanguage.allCases)
    func contextualPhrasesCoverEveryCommand(
        language: SupportedLanguage
    ) {
        #expect(language.voiceCommandContextualStrings.count == 4)
    }
}
