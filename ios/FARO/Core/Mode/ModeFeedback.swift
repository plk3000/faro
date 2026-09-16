import AudioToolbox
import UIKit

@MainActor
final class ModeFeedback: ModeFeedbackProviding {
    func confirmTransition(
        to mode: OperatingMode,
        language: SupportedLanguage
    ) {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(
            mode == .navigating ? .success : .warning
        )
        AudioServicesPlaySystemSound(mode.confirmationTone.rawValue)

        let announcement = NSAttributedString(
            string: language.text(mode.transitionAnnouncementKey),
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
