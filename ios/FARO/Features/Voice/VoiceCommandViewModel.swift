import Observation
import UIKit

@MainActor
protocol VoiceCommandFeedbackProviding: AnyObject {
    func announceFailure(
        _ message: String,
        language: SupportedLanguage
    )
}

@MainActor
final class VoiceCommandFeedback: VoiceCommandFeedbackProviding {
    func announceFailure(
        _ message: String,
        language: SupportedLanguage
    ) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
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

@MainActor
@Observable
final class VoiceCommandViewModel {
    private let recognizer: any SpeechRecognizing
    private let parser: VoiceCommandParser
    private let feedback: any VoiceCommandFeedbackProviding
    private var activeRequestID: UUID?

    private(set) var isPreparing = false
    private(set) var isListening = false
    private(set) var isProcessing = false
    private(set) var transcript = ""
    private(set) var statusMessage = AppMessage(.statusVoiceReady)
    private(set) var errorMessage: AppMessage?

    init(
        recognizer: (any SpeechRecognizing)? = nil,
        parser: VoiceCommandParser = VoiceCommandParser(),
        feedback: (any VoiceCommandFeedbackProviding)? = nil
    ) {
        self.recognizer = recognizer ?? OnDeviceSpeechRecognizer()
        self.parser = parser
        self.feedback = feedback ?? VoiceCommandFeedback()
    }

    var isActive: Bool {
        isPreparing || isListening || isProcessing
    }

    @discardableResult
    func beginListening(
        language: SupportedLanguage
    ) async -> Bool {
        guard !isActive else {
            return false
        }

        isPreparing = true
        let requestID = UUID()
        activeRequestID = requestID
        transcript = ""
        errorMessage = nil
        statusMessage = AppMessage(.statusVoicePreparing)
        defer { isPreparing = false }

        do {
            try await recognizer.start(
                language: language
            ) { [weak self] value in
                self?.transcript = value
            }
            guard activeRequestID == requestID else {
                recognizer.cancel()
                return false
            }
            isListening = true
            statusMessage = AppMessage(.statusVoiceListening)
            return true
        } catch {
            guard activeRequestID == requestID else {
                return false
            }
            activeRequestID = nil
            report(error, language: language)
            return false
        }
    }

    func finishListening(
        language: SupportedLanguage
    ) async -> VoiceCommand? {
        guard isListening else {
            return nil
        }

        isListening = false
        isProcessing = true
        let requestID = activeRequestID
        errorMessage = nil
        statusMessage = AppMessage(.statusVoiceProcessing)
        defer { isProcessing = false }

        do {
            let finalTranscript = try await recognizer.stop()
            guard activeRequestID == requestID else {
                return nil
            }
            transcript = finalTranscript
            guard let command = parser.parse(
                finalTranscript,
                language: language
            ) else {
                throw VoiceCommandError.unrecognized
            }
            statusMessage = AppMessage(
                .statusVoiceRecognized,
                argument: language.text(command.displayKey)
            )
            activeRequestID = nil
            return command
        } catch is CancellationError {
            activeRequestID = nil
            statusMessage = AppMessage(.statusVoiceReady)
            return nil
        } catch {
            guard activeRequestID == requestID else {
                return nil
            }
            activeRequestID = nil
            report(error, language: language)
            return nil
        }
    }

    func finishListeningAfterSpeechEndpoint(
        language: SupportedLanguage,
        onSpeechEndpoint: @MainActor () -> Void = {}
    ) async -> VoiceCommand? {
        guard isListening else {
            return nil
        }
        do {
            try await recognizer.waitForSpeechEndpoint()
        } catch is CancellationError {
            cancel()
            return nil
        } catch {
            recognizer.cancel()
            isListening = false
            activeRequestID = nil
            report(error, language: language)
            return nil
        }
        onSpeechEndpoint()
        return await finishListening(language: language)
    }

    func reportExecutionError(
        _ error: any Error,
        language: SupportedLanguage
    ) {
        report(error, language: language)
    }

    func markExecutionComplete() {
        statusMessage = AppMessage(.statusVoiceReady)
        errorMessage = nil
    }

    func cancel() {
        recognizer.cancel()
        activeRequestID = nil
        isPreparing = false
        isListening = false
        isProcessing = false
        transcript = ""
        errorMessage = nil
        statusMessage = AppMessage(.statusVoiceReady)
    }

    func statusText(language: SupportedLanguage) -> String {
        statusMessage.localized(in: language)
    }

    func errorText(language: SupportedLanguage) -> String? {
        errorMessage?.localized(in: language)
    }

    private func report(
        _ error: any Error,
        language: SupportedLanguage
    ) {
        let message = AppErrorMessage.message(
            for: error,
            language: language
        )
        statusMessage = message
        errorMessage = message
        feedback.announceFailure(
            message.localized(in: language),
            language: language
        )
    }
}
