import Foundation

enum SupportedLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case englishUS = "en-US"
    case spanishMexico = "es-MX"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
    var localizationResource: String {
        switch self {
        case .englishUS:
            "en"
        case .spanishMexico:
            "es-MX"
        }
    }

    var apiPrompt: String {
        switch self {
        case .englishUS:
            "Describe nearby objects, their relative position, and immediate obstacles in English."
        case .spanishMexico:
            "Describe en español los objetos cercanos, su posición relativa y los obstáculos inmediatos."
        }
    }

    var mockDescription: String {
        switch self {
        case .englishUS:
            "A chair is ahead and slightly to your left."
        case .spanishMexico:
            "Hay una silla delante de ti y un poco hacia la izquierda."
        }
    }
}

enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case followSystem
    case englishUS
    case spanishMexico

    static let storageKey = "faro.language-preference"

    var id: String { rawValue }

    var displayKey: AppStringKey {
        switch self {
        case .followSystem:
            .languageFollowSystem
        case .englishUS:
            .languageEnglishUS
        case .spanishMexico:
            .languageSpanishMexico
        }
    }

    func resolve(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> SupportedLanguage {
        switch self {
        case .englishUS:
            return .englishUS
        case .spanishMexico:
            return .spanishMexico
        case .followSystem:
            guard let identifier = preferredLanguages.first else {
                return .englishUS
            }
            let languageCode = Locale(identifier: identifier)
                .language
                .languageCode?
                .identifier
            switch languageCode {
            case "es":
                return .spanishMexico
            case "en":
                return .englishUS
            default:
                return .englishUS
            }
        }
    }
}
