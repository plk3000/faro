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
        #expect(
            SupportedLanguage.englishUS.text(.actionWhereAmI)
                == "Where am I?"
        )
        #expect(
            SupportedLanguage.spanishMexico.text(.actionWhereAmI)
                == "¿Dónde estoy?"
        )
        #expect(
            SupportedLanguage.spanishMexico.text(
                .statusSavedPlaceView,
                arguments: ["2", "Cocina"]
            ) == "Vista 2 de Cocina guardada"
        )
    }

    @Test(arguments: SupportedLanguage.allCases)
    func everyApplicationKeyExistsInTheSelectedCatalog(
        language: SupportedLanguage
    ) {
        for key in AppStringKey.allCases {
            #expect(
                language.text(key) != key.rawValue,
                "Missing \(language.rawValue) value for \(key.rawValue)"
            )
        }
    }
}
