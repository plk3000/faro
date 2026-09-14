import AudioToolbox
import UIKit

@MainActor
protocol CaptureFeedbackProviding: AnyObject {
    func announceSuccess()
    func announceFailure(_ message: String)
}

@MainActor
final class CaptureFeedback: CaptureFeedbackProviding {
    func announceSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1108)
        UIAccessibility.post(
            notification: .announcement,
            argument: "Image captured and saved"
        )
    }

    func announceFailure(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }
}
