import AudioToolbox
import Observation
import UIKit

enum HandsFreePreference {
    static let storageKey = "faro.hands-free-enabled"
}

struct HandsFreeActivationPolicy: Sendable {
    static func shouldArm(
        isEnabled: Bool,
        isSceneActive: Bool,
        isEnrollmentPresented: Bool,
        isCaptureBusy: Bool,
        isVoiceSessionActive: Bool
    ) -> Bool {
        isEnabled
            && isSceneActive
            && !isEnrollmentPresented
            && !isCaptureBusy
            && !isVoiceSessionActive
    }
}

@MainActor
protocol WakePhraseDetecting: AnyObject {
    func start(
        language: SupportedLanguage,
        onWakePhrase: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws
    func stop()
}

@MainActor
protocol HandsFreeFeedbackProviding: AnyObject {
    func confirmArmed() async
    func confirmWakePhrase() async
}

struct SystemSoundAwaiter: Sendable {
    typealias Playback = @Sendable (
        SystemSoundID,
        @escaping @Sendable () -> Void
    ) -> Void

    private let playback: Playback

    init(
        playback: @escaping Playback = {
            soundID,
            completion in
            AudioServicesPlaySystemSoundWithCompletion(
                soundID,
                completion
            )
        }
    ) {
        self.playback = playback
    }

    nonisolated func play(_ soundID: SystemSoundID) async {
        await withCheckedContinuation { continuation in
            playback(soundID) {
                continuation.resume()
            }
        }
    }
}

@MainActor
final class HandsFreeFeedback: HandsFreeFeedbackProviding {
    private let soundAwaiter: SystemSoundAwaiter

    init(soundAwaiter: SystemSoundAwaiter = SystemSoundAwaiter()) {
        self.soundAwaiter = soundAwaiter
    }

    func confirmArmed() async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        await soundAwaiter.play(1117)
    }

    func confirmWakePhrase() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await soundAwaiter.play(1118)
    }
}

struct HandsFreeActivationConfiguration: Sendable {
    static let siriHandoff = HandsFreeActivationConfiguration(
        retryDelays: [
            .milliseconds(450),
            .milliseconds(500),
            .seconds(1),
            .seconds(1)
        ]
    )

    let retryDelays: [Duration]
}

enum HandsFreeListeningState: Equatable, Sendable {
    case disabled
    case preparing
    case listeningForWakePhrase
    case wakePhraseDetected
    case recordingCommand
    case processingCommand
    case executingCommand

    var statusKey: AppStringKey {
        switch self {
        case .disabled:
            .statusHandsFreeOff
        case .preparing:
            .statusHandsFreePreparing
        case .listeningForWakePhrase:
            .statusHandsFreeListening
        case .wakePhraseDetected:
            .statusHandsFreeWakeDetected
        case .recordingCommand:
            .statusHandsFreeRecording
        case .processingCommand:
            .statusHandsFreeProcessing
        case .executingCommand:
            .statusHandsFreeExecuting
        }
    }
}

@MainActor
@Observable
final class HandsFreeVoiceViewModel {
    private let detector: any WakePhraseDetecting
    private let feedback: any HandsFreeFeedbackProviding
    private let failureFeedback: any VoiceCommandFeedbackProviding
    private let configuration: HandsFreeActivationConfiguration
    private var activeRequestID: UUID?
    private var wakeFeedbackTask: Task<Void, Never>?

    private(set) var state: HandsFreeListeningState = .disabled
    private(set) var errorMessage: AppMessage?

    init(
        detector: (any WakePhraseDetecting)? = nil,
        feedback: (any HandsFreeFeedbackProviding)? = nil,
        failureFeedback: (any VoiceCommandFeedbackProviding)? = nil,
        configuration: HandsFreeActivationConfiguration = .siriHandoff
    ) {
        self.detector = detector ?? OnDeviceWakePhraseDetector()
        self.feedback = feedback ?? HandsFreeFeedback()
        self.failureFeedback = failureFeedback ?? VoiceCommandFeedback()
        self.configuration = configuration
    }

    var isListeningForWakePhrase: Bool {
        state == .listeningForWakePhrase
    }

    var isUsingMicrophone: Bool {
        switch state {
        case .preparing,
             .listeningForWakePhrase,
             .recordingCommand:
            true
        case .disabled,
             .wakePhraseDetected,
             .processingCommand,
             .executingCommand:
            false
        }
    }

    @discardableResult
    func arm(
        language: SupportedLanguage,
        onWakePhrase: @escaping @MainActor () -> Void
    ) async -> Bool {
        detector.stop()
        wakeFeedbackTask?.cancel()
        wakeFeedbackTask = nil
        let requestID = UUID()
        activeRequestID = requestID
        state = .preparing
        errorMessage = nil
        var lastError: (any Error)?

        for delay in configuration.retryDelays {
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                guard activeRequestID == requestID else {
                    return false
                }
                try await detector.start(
                    language: language
                ) { [weak self] in
                    self?.handleWakePhrase(
                        requestID: requestID,
                        onWakePhrase: onWakePhrase
                    )
                } onFailure: { [weak self] error in
                    self?.handleDetectorFailure(
                        error,
                        requestID: requestID,
                        language: language
                    )
                }
                guard activeRequestID == requestID else {
                    detector.stop()
                    return false
                }
                await feedback.confirmArmed()
                try Task.checkCancellation()
                guard activeRequestID == requestID else {
                    detector.stop()
                    return false
                }
                state = .listeningForWakePhrase
                return true
            } catch is CancellationError {
                disarm()
                return false
            } catch {
                detector.stop()
                lastError = error
                if !shouldRetry(error) {
                    break
                }
            }
        }

        activeRequestID = nil
        state = .disabled
        if let lastError {
            report(lastError, language: language)
        }
        return false
    }

    func beginCommandCapture() {
        detector.stop()
        activeRequestID = nil
        state = .recordingCommand
        errorMessage = nil
    }

    func beginCommandProcessing() {
        state = .processingCommand
    }

    func beginCommandExecution() {
        state = .executingCommand
    }

    func disarm() {
        detector.stop()
        wakeFeedbackTask?.cancel()
        wakeFeedbackTask = nil
        activeRequestID = nil
        state = .disabled
        errorMessage = nil
    }

    func statusText(language: SupportedLanguage) -> String {
        language.text(state.statusKey)
    }

    func errorText(language: SupportedLanguage) -> String? {
        errorMessage?.localized(in: language)
    }

    private func handleWakePhrase(
        requestID: UUID,
        onWakePhrase: @escaping @MainActor () -> Void
    ) {
        guard activeRequestID == requestID,
              state == .listeningForWakePhrase else {
            return
        }
        detector.stop()
        activeRequestID = nil
        state = .wakePhraseDetected
        wakeFeedbackTask?.cancel()
        wakeFeedbackTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await feedback.confirmWakePhrase()
            guard !Task.isCancelled,
                  state == .wakePhraseDetected else {
                return
            }
            wakeFeedbackTask = nil
            onWakePhrase()
        }
    }

    private func shouldRetry(_ error: any Error) -> Bool {
        guard let speechError = error as? SpeechRecognitionError else {
            return false
        }
        return switch speechError {
        case .audioInputUnavailable,
             .recognizerUnavailable,
             .recognitionFailed:
            true
        case .speechPermissionDenied,
             .microphonePermissionDenied,
             .onDeviceRecognitionUnavailable,
             .noSpeechDetected,
             .alreadyListening:
            false
        }
    }

    private func handleDetectorFailure(
        _ error: any Error,
        requestID: UUID,
        language: SupportedLanguage
    ) {
        guard activeRequestID == requestID else {
            return
        }
        detector.stop()
        activeRequestID = nil
        state = .disabled
        report(error, language: language)
    }

    private func report(
        _ error: any Error,
        language: SupportedLanguage
    ) {
        let message = AppErrorMessage.message(
            for: error,
            language: language
        )
        errorMessage = message
        failureFeedback.announceFailure(
            message.localized(in: language),
            language: language
        )
    }
}
