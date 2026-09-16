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

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var activeSessionID: UUID?
    private var transcriptHandler: (@MainActor (String) -> Void)?
    private var latestTranscript = ""
    private var recognitionError: Error?
    private var receivedFinalResult = false
    private var hasInputTap = false
    private var isListening = false

    func start(
        language: SupportedLanguage,
        onTranscript: @escaping @MainActor (String) -> Void
    ) async throws {
        guard !isListening else {
            throw SpeechRecognitionError.alreadyListening
        }

        try await authorizeSpeechRecognition()
        try await authorizeMicrophone()

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
        recognitionError = nil
        receivedFinalResult = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = language.voiceCommandContextualStrings
        recognitionRequest = request

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers, .allowBluetoothHFP]
            )
            try audioSession.setActive(
                true,
                options: .notifyOthersOnDeactivation
            )

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechRecognitionError.audioInputUnavailable
            }
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: format
            ) { buffer, _ in
                request.append(buffer)
            }
            hasInputTap = true

            recognitionTask = recognizer.recognitionTask(
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
                        self.receivedFinalResult = result.isFinal
                        self.transcriptHandler?(value)
                    }
                    if let error {
                        self.recognitionError = error
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch let error as SpeechRecognitionError {
            cancel()
            throw error
        } catch {
            cancel()
            throw SpeechRecognitionError.audioInputUnavailable
        }
    }

    func stop() async throws -> String {
        guard isListening else {
            throw SpeechRecognitionError.noSpeechDetected
        }

        isListening = false
        stopAudioInput()
        defer { cleanup() }

        var unchangedIntervals = 0
        var previousTranscript = latestTranscript
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(125))
            try Task.checkCancellation()
            if receivedFinalResult {
                break
            }
            if latestTranscript == previousTranscript,
               !latestTranscript.isEmpty {
                unchangedIntervals += 1
                if unchangedIntervals >= 4 {
                    break
                }
            } else {
                previousTranscript = latestTranscript
                unchangedIntervals = 0
            }
        }

        let result = latestTranscript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !result.isEmpty else {
            if recognitionError != nil {
                throw SpeechRecognitionError.recognitionFailed
            }
            throw SpeechRecognitionError.noSpeechDetected
        }
        return result
    }

    func cancel() {
        isListening = false
        stopAudioInput()
        cleanup()
    }

    private func authorizeSpeechRecognition() async throws {
        let current = SFSpeechRecognizer.authorizationStatus()
        let status: SFSpeechRecognizerAuthorizationStatus
        if current == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization {
                    continuation.resume(returning: $0)
                }
            }
        } else {
            status = current
        }
        guard status == .authorized else {
            throw SpeechRecognitionError.speechPermissionDenied
        }
    }

    private func authorizeMicrophone() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard granted else {
            throw SpeechRecognitionError.microphonePermissionDenied
        }
    }

    private func stopAudioInput() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcriptHandler = nil
        activeSessionID = nil
        latestTranscript = ""
        recognitionError = nil
        receivedFinalResult = false

        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            Self.logger.error(
                "Could not deactivate speech audio session: \(error)"
            )
        }
    }
}
