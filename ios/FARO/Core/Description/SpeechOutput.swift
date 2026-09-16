@preconcurrency import AVFoundation
import UIKit

@MainActor
protocol SpeechOutputProviding: AnyObject {
    func speak(
        _ text: String,
        language: SupportedLanguage
    ) throws
    func stop()
    func waitUntilFinished() async
}

enum SpeechOutputError:
    Error,
    LocalizedError,
    AppMessageProviding
{
    case audioSessionUnavailable
    case voiceUnavailable(String)

    var appMessage: AppMessage {
        switch self {
        case .audioSessionUnavailable:
            AppMessage(.errorAudioUnavailable)
        case let .voiceUnavailable(language):
            AppMessage(.errorVoiceUnavailable, argument: language)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}

struct SpeechOutputConfiguration: Equatable, Sendable {
    static let accessibleDefault = SpeechOutputConfiguration(
        rate: 0.3,
        preUtteranceDelay: 0.12,
        phraseDelay: 0.24
    )

    let rate: Float
    let preUtteranceDelay: TimeInterval
    let phraseDelay: TimeInterval
}

enum SpeechPhrasePacer {
    static func phrases(
        from text: String,
        language: SupportedLanguage
    ) -> [String] {
        let breakWords: Set<String>
        switch language {
        case .englishUS:
            breakWords = ["and", "but", "while", "with"]
        case .spanishMexico:
            breakWords = ["y", "pero", "mientras", "con"]
        }

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

    static func voiceOverText(
        from text: String,
        language: SupportedLanguage
    ) -> String {
        phrases(from: text, language: language)
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
    private var voiceOverOutputEndDate: Date?

    init(
        configuration: SpeechOutputConfiguration = .accessibleDefault
    ) {
        self.configuration = configuration
    }

    func speak(
        _ text: String,
        language: SupportedLanguage
    ) throws {
        stop()
        let phrases = SpeechPhrasePacer.phrases(
            from: text,
            language: language
        )
        guard !phrases.isEmpty else {
            return
        }

        if UIAccessibility.isVoiceOverRunning {
            let wordCount = text.split(
                whereSeparator: \.isWhitespace
            ).count
            voiceOverOutputEndDate = Date().addingTimeInterval(
                max(1, Double(wordCount) * 0.55)
            )
            let announcement = NSAttributedString(
                string: SpeechPhrasePacer.voiceOverText(
                    from: text,
                    language: language
                ),
                attributes: [
                    .accessibilitySpeechLanguage: language.rawValue
                ]
            )
            UIAccessibility.post(
                notification: .announcement,
                argument: announcement
            )
            return
        }
        voiceOverOutputEndDate = nil

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
            language: language.rawValue
        ) else {
            throw SpeechOutputError.voiceUnavailable(
                language.rawValue
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
        voiceOverOutputEndDate = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func waitUntilFinished() async {
        while synthesizer.isSpeaking {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }
        while let endDate = voiceOverOutputEndDate,
              endDate > Date() {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }
        voiceOverOutputEndDate = nil
    }
}
