@preconcurrency import AVFoundation
import UIKit

@MainActor
protocol SpeechOutputProviding: AnyObject {
    func speak(_ text: String) throws
    func stop()
}

enum SpeechOutputError: Error, LocalizedError {
    case audioSessionUnavailable

    var errorDescription: String? {
        "FARO could not start spoken audio."
    }
}

@MainActor
final class SpeechOutput: NSObject, SpeechOutputProviding {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) throws {
        stop()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: text
            )
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechOutputError.audioSessionUnavailable
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
