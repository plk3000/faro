import AudioToolbox
import UIKit

@MainActor
protocol CaptureFeedbackProviding: AnyObject {
    func announceSuccess(language: SupportedLanguage)
    func announceFailure(
        _ message: String,
        language: SupportedLanguage
    )
}

@MainActor
final class CaptureFeedback: CaptureFeedbackProviding {
    func announceSuccess(language: SupportedLanguage) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1108)
        announce(
            language.text(.statusImageCapturedSaved),
            language: language
        )
    }

    func announceFailure(
        _ message: String,
        language: SupportedLanguage
    ) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        announce(message, language: language)
    }

    private func announce(
        _ message: String,
        language: SupportedLanguage
    ) {
        let announcement = NSAttributedString(
            string: message,
            attributes: [
                .accessibilitySpeechLanguage: language.rawValue
            ]
        )
        UIAccessibility.post(
            notification: .announcement,
            argument: announcement
        )
    }
}
