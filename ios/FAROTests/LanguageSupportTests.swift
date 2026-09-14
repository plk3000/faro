import Foundation
import Testing
@testable import FARO

struct LanguageSupportTests {
    @Test
    func explicitPreferencesIgnoreSystemLanguage() {
        #expect(
            LanguagePreference.englishUS.resolve(
                preferredLanguages: ["es-MX"]
            ) == .englishUS
        )
        #expect(
            LanguagePreference.spanishMexico.resolve(
                preferredLanguages: ["en-US"]
            ) == .spanishMexico
        )
    }

    @Test(arguments: [
        (["es-MX"], SupportedLanguage.spanishMexico),
        (["es-ES"], SupportedLanguage.spanishMexico),
        (["fr-FR", "en-GB"], SupportedLanguage.englishUS),
        (["fr-FR", "es-MX"], SupportedLanguage.englishUS),
        (["fr-FR"], SupportedLanguage.englishUS)
    ])
    func followSystemResolvesSupportedLanguage(
        preferredLanguages: [String],
        expected: SupportedLanguage
    ) {
        #expect(
            LanguagePreference.followSystem.resolve(
                preferredLanguages: preferredLanguages
            ) == expected
        )
    }

    @Test
    func catalogsContainEnglishAndSpanishValues() {
        #expect(
            SupportedLanguage.englishUS.text(.actionDescribe)
                == "Describe scene"
        )
        #expect(
            SupportedLanguage.spanishMexico.text(.actionDescribe)
                == "Describir escena"
        )
        #expect(
            SupportedLanguage.englishUS.text(
                .sceneDescriptionLabel,
                argument: "A chair is ahead."
            ) == "Scene description: A chair is ahead."
        )
        #expect(
            SupportedLanguage.spanishMexico.text(
                .sceneDescriptionLabel,
                argument: "Hay una silla delante."
            ) == "Descripción de la escena: Hay una silla delante."
        )
    }
}
