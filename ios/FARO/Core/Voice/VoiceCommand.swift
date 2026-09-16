import Foundation

enum VoiceCommand: Equatable, Sendable {
    case describeScene
    case whereAmI
    case rememberPlace(label: String)
    case whatIsAhead
    case startNavigating
    case stopNavigating

    var displayKey: AppStringKey {
        switch self {
        case .describeScene:
            .voiceCommandDescribe
        case .whereAmI:
            .voiceCommandWhereAmI
        case .rememberPlace:
            .voiceCommandRememberPlace
        case .whatIsAhead:
            .voiceCommandWhatIsAhead
        case .startNavigating:
            .voiceCommandStartNavigating
        case .stopNavigating:
            .voiceCommandStopNavigating
        }
    }

    var requiresNavigating: Bool {
        switch self {
        case .whereAmI, .whatIsAhead:
            true
        case .describeScene,
             .rememberPlace,
             .startNavigating,
             .stopNavigating:
            false
        }
    }
}

enum VoiceCommandError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case unrecognized
    case navigatingModeRequired

    var appMessage: AppMessage {
        switch self {
        case .unrecognized:
            AppMessage(.errorVoiceCommandUnrecognized)
        case .navigatingModeRequired:
            AppMessage(.errorVoiceCommandRequiresNavigating)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}

extension SupportedLanguage {
    var voiceCommandContextualStrings: [String] {
        switch self {
        case .englishUS:
            [
                "describe",
                "where am I",
                "remember this as",
                "what is ahead",
                "start navigation",
                "stop navigation"
            ]
        case .spanishMexico:
            [
                "describe",
                "dónde estoy",
                "recuerda este lugar como",
                "qué hay delante",
                "inicia navegación",
                "detén navegación"
            ]
        }
    }
}
