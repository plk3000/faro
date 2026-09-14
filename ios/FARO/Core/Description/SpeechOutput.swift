@preconcurrency import AVFoundation
import UIKit

@MainActor
protocol SpeechOutputProviding: AnyObject {
    func speak(_ text: String) throws
    func stop()
}

enum SpeechOutputError: Error, LocalizedError {
    case audioSessionUnavailable
    case voiceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .audioSessionUnavailable:
            "FARO no pudo iniciar el audio."
        case let .voiceUnavailable(language):
            "FARO no encontró una voz para \(language)."
        }
    }
}

struct SpeechOutputConfiguration: Equatable, Sendable {
    static let accessibleDefault = SpeechOutputConfiguration(
        rate: 0.3,
        preUtteranceDelay: 0.12,
        phraseDelay: 0.24,
        languageCode: FAROLanguage.outputLocaleIdentifier
    )

    let rate: Float
    let preUtteranceDelay: TimeInterval
    let phraseDelay: TimeInterval
    let languageCode: String
}

enum SpeechPhrasePacer {
    private static let breakWords = Set([
        "and",
        "but",
        "while",
        "with",
        "y",
        "pero",
        "mientras",
        "con"
    ])

    static func phrases(from text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            return []
        }

        var phrases: [String] = []
        var current: [String] = []

        for word in words {
            let normalized = word
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()
            if breakWords.contains(normalized), current.count >= 3 {
                phrases.append(current.joined(separator: " "))
                current.removeAll(keepingCapacity: true)
            }

            current.append(word)
            if word.last?.isPunctuation == true || current.count >= 7 {
                phrases.append(current.joined(separator: " "))
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            phrases.append(current.joined(separator: " "))
        }
        return phrases
    }

    static func voiceOverText(from text: String) -> String {
        phrases(from: text)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: .punctuationCharacters)
            }
            .filter { !$0.isEmpty }
            .map {
                $0.prefix(1).uppercased() + $0.dropFirst()
            }
            .joined(separator: ". ")
    }
}

@MainActor
final class SpeechOutput: NSObject, SpeechOutputProviding {
    private let synthesizer = AVSpeechSynthesizer()
    private let configuration: SpeechOutputConfiguration

    init(
        configuration: SpeechOutputConfiguration = .accessibleDefault
    ) {
        self.configuration = configuration
    }

    func speak(_ text: String) throws {
        stop()
        let phrases = SpeechPhrasePacer.phrases(from: text)
        guard !phrases.isEmpty else {
            return
        }

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: SpeechPhrasePacer.voiceOverText(from: text)
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

        guard let voice = AVSpeechSynthesisVoice(
            language: configuration.languageCode
        ) else {
            throw SpeechOutputError.voiceUnavailable(
                configuration.languageCode
            )
        }

        for (index, phrase) in phrases.enumerated() {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = voice
            utterance.rate = configuration.rate
            utterance.preUtteranceDelay = index == 0
                ? configuration.preUtteranceDelay
                : 0
            utterance.postUtteranceDelay = configuration.phraseDelay
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
