@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

@MainActor
protocol SpeechRecognizing: AnyObject {
    func start(
        language: SupportedLanguage,
        onTranscript: @escaping @MainActor (String) -> Void
    ) async throws
    func waitForSpeechEndpoint() async throws
    func stop() async throws -> String
    func cancel()
}

enum SpeechRecognitionError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
    case audioInputUnavailable
    case recognitionFailed
    case noSpeechDetected
    case alreadyListening

    var appMessage: AppMessage {
        switch self {
        case .speechPermissionDenied:
            AppMessage(.errorSpeechPermission)
        case .microphonePermissionDenied:
            AppMessage(.errorMicrophonePermission)
        case .recognizerUnavailable:
            AppMessage(.errorSpeechRecognizerUnavailable)
        case .onDeviceRecognitionUnavailable:
            AppMessage(.errorOnDeviceSpeechUnavailable)
        case .audioInputUnavailable:
            AppMessage(.errorSpeechAudioInput)
        case .recognitionFailed:
            AppMessage(.errorSpeechRecognition)
        case .noSpeechDetected:
            AppMessage(.errorSpeechNoInput)
        case .alreadyListening:
            AppMessage(.errorSpeechAlreadyListening)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}

@MainActor
final class OnDeviceSpeechRecognizer: SpeechRecognizing {
    private static let logger = Logger(
        subsystem: "com.jdsolissmith.faro",
        category: "SpeechRecognition"
    )

    private var audioRecorder: AVAudioRecorder?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechURLRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeSessionID: UUID?
    private var recordingURL: URL?
    private var contextualStrings: [String] = []
    private var transcriptHandler: (@MainActor (String) -> Void)?
    private var recognitionContinuation:
        CheckedContinuation<String, Error>?
    private var recognitionTimeoutTask: Task<Void, Never>?
    private var latestTranscript = ""
    private var isListening = false
    private var ownsAudioSession = false

    func start(
        language: SupportedLanguage,
        onTranscript: @escaping @MainActor (String) -> Void
    ) async throws {
        guard !isListening else {
            throw SpeechRecognitionError.alreadyListening
        }

        try await VoiceAuthorization.requireSpeechRecognition()
        try Task.checkCancellation()
        try await VoiceAuthorization.requireMicrophone()
        try Task.checkCancellation()

        guard let recognizer = SFSpeechRecognizer(
            locale: language.locale
        ),
        recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechRecognitionError
                .onDeviceRecognitionUnavailable
        }

        cancel()
        let sessionID = UUID()
        activeSessionID = sessionID
        transcriptHandler = onTranscript
        latestTranscript = ""
        speechRecognizer = recognizer
        contextualStrings = language.voiceCommandContextualStrings

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "faro-voice-\(sessionID.uuidString).m4a"
            )
        recordingURL = url

        do {
            try Task.checkCancellation()
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.allowBluetoothHFP]
            )
            try audioSession.setActive(
                true,
                options: .notifyOthersOnDeactivation
            )
            ownsAudioSession = true

            let recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 32_000,
                    AVEncoderAudioQualityKey:
                        AVAudioQuality.high.rawValue
                ]
            )
            audioRecorder = recorder
            recorder.isMeteringEnabled = true
            try Task.checkCancellation()
            guard recorder.prepareToRecord(), recorder.record() else {
                throw SpeechRecognitionError.audioInputUnavailable
            }
            isListening = true
        } catch is CancellationError {
            cancel()
            throw CancellationError()
        } catch let error as SpeechRecognitionError {
            cancel()
            throw error
        } catch {
            Self.logger.error(
                "Could not start voice recording: \(error)"
            )
            cancel()
            throw SpeechRecognitionError.audioInputUnavailable
        }
    }

    func waitForSpeechEndpoint() async throws {
        guard isListening, let recorder = audioRecorder else {
            throw SpeechRecognitionError.noSpeechDetected
        }

        var detector = SpeechEndpointDetector()
        while isListening {
            try await Task.sleep(
                for: .seconds(detector.configuration.pollInterval)
            )
            try Task.checkCancellation()
            guard recorder === audioRecorder else {
                throw CancellationError()
            }
            recorder.updateMeters()
            if detector.observe(
                averagePower: recorder.averagePower(forChannel: 0)
            ) {
                return
            }
        }
        throw CancellationError()
    }

    func stop() async throws -> String {
        guard isListening,
              let recordingURL,
              let speechRecognizer,
              let sessionID = activeSessionID else {
            throw SpeechRecognitionError.noSpeechDetected
        }

        isListening = false
        audioRecorder?.stop()
        audioRecorder = nil
        deactivateRecordingAudioSession()

        let request = SFSpeechURLRecognitionRequest(
            url: recordingURL
        )
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = contextualStrings
        recognitionRequest = request

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation {
                continuation in
                recognitionContinuation = continuation
                recognitionTask = speechRecognizer.recognitionTask(
                    with: request
                ) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.activeSessionID == sessionID else {
                            return
                        }
                        if let result {
                            let value = result.bestTranscription
                                .formattedString
                            self.latestTranscript = value
                            self.transcriptHandler?(value)
                            if result.isFinal {
                                self.completeRecognition(
                                    transcript: value,
                                    emptyTranscriptError: .noSpeechDetected
                                )
                                return
                            }
                        }
                        if error != nil {
                            self.completeRecognition(
                                transcript: self.latestTranscript,
                                emptyTranscriptError: .recognitionFailed
                            )
                        }
                    }
                }
                recognitionTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(10))
                    } catch {
                        return
                    }
                    self?.failTimedOutRecognition()
                }
                if Task.isCancelled {
                    cancel()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func cancel() {
        isListening = false
        audioRecorder?.stop()
        audioRecorder = nil
        deactivateRecordingAudioSession()

        let continuation = recognitionContinuation
        recognitionContinuation = nil
        recognitionTimeoutTask?.cancel()
        recognitionTimeoutTask = nil
        let task = recognitionTask
        task?.cancel()
        resetRecognitionState()
        removeRecordingWhenReleased(by: task)
        continuation?.resume(throwing: CancellationError())
    }

    private func deactivateRecordingAudioSession() {
        guard ownsAudioSession else {
            return
        }
        ownsAudioSession = false
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            Self.logger.error(
                "Could not deactivate recording audio session: \(error)"
            )
        }
    }

    private func completeRecognition(
        transcript: String,
        emptyTranscriptError: SpeechRecognitionError
    ) {
        let value = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let result: Result<String, Error> = value.isEmpty
            ? .failure(emptyTranscriptError)
            : .success(value)
        finishRecognition(with: result)
    }

    private func failTimedOutRecognition() {
        recognitionTask?.cancel()
        finishRecognition(
            with: .failure(SpeechRecognitionError.recognitionFailed)
        )
    }

    private func finishRecognition(
        with result: Result<String, Error>
    ) {
        guard let continuation = recognitionContinuation else {
            return
        }
        recognitionContinuation = nil
        recognitionTimeoutTask?.cancel()
        recognitionTimeoutTask = nil
        let task = recognitionTask
        resetRecognitionState()
        removeRecordingWhenReleased(by: task)
        continuation.resume(with: result)
    }

    private func resetRecognitionState() {
        activeSessionID = nil
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        contextualStrings = []
        transcriptHandler = nil
        latestTranscript = ""
    }

    private func removeRecordingWhenReleased(
        by recognitionTask: SFSpeechRecognitionTask?
    ) {
        guard let recordingURL else {
            return
        }
        self.recordingURL = nil

        guard let recognitionTask else {
            Self.removeRecording(at: recordingURL)
            return
        }

        Task { @MainActor [recordingURL] in
            for _ in 0..<40 {
                guard recognitionTask.state != .completed else {
                    break
                }
                try? await Task.sleep(for: .milliseconds(125))
            }
            Self.removeRecording(at: recordingURL)
        }
    }

    private static func removeRecording(at recordingURL: URL) {
        do {
            try FileManager.default.removeItem(
                at: recordingURL
            )
        } catch {
            if (error as NSError).code != NSFileNoSuchFileError {
                logger.error(
                    "Could not remove voice recording: \(error)"
                )
            }
        }
    }
}
