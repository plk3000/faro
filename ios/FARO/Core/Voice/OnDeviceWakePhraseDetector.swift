@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

@MainActor
final class OnDeviceWakePhraseDetector: WakePhraseDetecting {
    private static let logger = Logger(
        subsystem: "com.jdsolissmith.faro",
        category: "WakePhrase"
    )

    private let matcher: WakePhraseMatcher
    private var microphoneCapture: WakePhraseMicrophoneCapture?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var speechDetector: SpeechDetector?
    private var resultsTask: Task<Void, Never>?
    private var activeSessionID: UUID?
    private var reservedLocale: Locale?
    private var transcriptAccumulator =
        WakePhraseTranscriptAccumulator()
    private var ownsAudioSession = false

    init(matcher: WakePhraseMatcher = WakePhraseMatcher()) {
        self.matcher = matcher
    }

    func start(
        language: SupportedLanguage,
        onWakePhrase: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws {
        stop()
        try await VoiceAuthorization.requireSpeechRecognition()
        try await VoiceAuthorization.requireMicrophone()

        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: language.locale
              ) else {
            throw SpeechRecognitionError
                .onDeviceRecognitionUnavailable
        }

        do {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [
                    .volatileResults,
                    .fastResults
                ],
                attributeOptions: []
            )
            let speechDetector = SpeechDetector(
                detectionOptions: .init(
                    sensitivityLevel: .medium
                ),
                reportResults: false
            )
            let modules: [any SpeechModule] = [
                speechDetector,
                transcriber
            ]
            try await prepareAssets(
                for: locale,
                modules: modules
            )
            guard let targetFormat =
                    await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: modules
                    ) else {
                throw SpeechRecognitionError.audioInputUnavailable
            }

            let context = AnalysisContext()
            context.contextualStrings = [
                .general: language.wakePhraseContextualStrings
            ]
            let analyzer = SpeechAnalyzer(
                modules: modules,
                options: .init(
                    priority: .userInitiated,
                    modelRetention: .processLifetime
                )
            )
            try await analyzer.setContext(context)

            let (inputSequence, inputContinuation) =
                AsyncStream.makeStream(of: AnalyzerInput.self)

            try configureAudioSession()
            let microphoneCapture = try WakePhraseMicrophoneCapture(
                targetFormat: targetFormat,
                inputContinuation: inputContinuation
            )

            let sessionID = UUID()
            activeSessionID = sessionID
            transcriptAccumulator =
                WakePhraseTranscriptAccumulator()
            self.analyzer = analyzer
            self.transcriber = transcriber
            self.speechDetector = speechDetector
            self.microphoneCapture = microphoneCapture

            resultsTask = Task { @MainActor [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self,
                              self.activeSessionID == sessionID else {
                            return
                        }
                        self.process(
                            result,
                            language: language,
                            onWakePhrase: onWakePhrase
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard let self,
                          self.activeSessionID == sessionID else {
                        return
                    }
                    Self.logger.error(
                        "Wake transcription failed: \(error)"
                    )
                    onFailure(
                        SpeechRecognitionError.recognitionFailed
                    )
                }
            }

            try await analyzer.start(inputSequence: inputSequence)
            try microphoneCapture.start()
        } catch is CancellationError {
            stop()
            throw CancellationError()
        } catch let error as SpeechRecognitionError {
            stop()
            throw error
        } catch {
            Self.logger.error(
                "Could not start wake phrase detection: \(error)"
            )
            stop()
            throw SpeechRecognitionError.recognizerUnavailable
        }
    }

    func stop() {
        activeSessionID = nil
        microphoneCapture?.stop()
        microphoneCapture = nil
        resultsTask?.cancel()
        resultsTask = nil

        if let analyzer {
            Task {
                await analyzer.cancelAndFinishNow()
            }
        }
        analyzer = nil
        transcriber = nil
        speechDetector = nil
        transcriptAccumulator =
            WakePhraseTranscriptAccumulator()
        deactivateAudioSession()
    }

    private func process(
        _ result: SpeechTranscriber.Result,
        language: SupportedLanguage,
        onWakePhrase: @escaping @MainActor () -> Void
    ) {
        let text = String(result.text.characters)
        guard transcriptAccumulator.observe(
            text,
            language: language,
            matcher: matcher
        ) else {
            return
        }

        onWakePhrase()
    }

    private func prepareAssets(
        for locale: Locale,
        modules: [any SpeechModule]
    ) async throws {
        if let reservedLocale,
           reservedLocale.identifier(.bcp47)
            != locale.identifier(.bcp47) {
            await AssetInventory.release(
                reservedLocale: reservedLocale
            )
            self.reservedLocale = nil
        }

        if reservedLocale == nil {
            _ = try await AssetInventory.reserve(locale: locale)
            reservedLocale = locale
        }

        if let request =
            try await AssetInventory.assetInstallationRequest(
                supporting: modules
            ) {
            try await request.downloadAndInstall()
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [
                .defaultToSpeaker,
                .allowBluetoothHFP
            ]
        )
        try audioSession.setActive(
            true,
            options: .notifyOthersOnDeactivation
        )
        ownsAudioSession = true
    }

    private func deactivateAudioSession() {
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
                "Could not deactivate wake audio session: \(error)"
            )
        }
    }
}

private final class WakePhraseMicrophoneCapture:
    @unchecked Sendable
{
    private let audioEngine = AVAudioEngine()
    private let converter: AVAudioConverter
    private let inputContinuation:
        AsyncStream<AnalyzerInput>.Continuation
    private let targetFormat: AVAudioFormat
    private var hasInputTap = false

    init(
        targetFormat: AVAudioFormat,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        self.targetFormat = targetFormat
        self.inputContinuation = inputContinuation

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let converter = AVAudioConverter(
                  from: inputFormat,
                  to: targetFormat
              ) else {
            throw SpeechRecognitionError.audioInputUnavailable
        }
        self.converter = converter

        inputNode.installTap(
            onBus: 0,
            bufferSize: 4_096,
            format: nil
        ) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        hasInputTap = true
    }

    func start() throws {
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stop()
            throw SpeechRecognitionError.audioInputUnavailable
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        inputContinuation.finish()
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let frameCapacity = AVAudioFrameCount(
            ceil(
                Double(buffer.frameLength)
                    * targetFormat.sampleRate
                    / converter.inputFormat.sampleRate
            )
        )
        guard frameCapacity > 0,
              let convertedBuffer = AVAudioPCMBuffer(
                  pcmFormat: targetFormat,
                  frameCapacity: frameCapacity
              ) else {
            return
        }

        var conversionError: NSError?
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let sourceBuffer = buffer
        converter.convert(
            to: convertedBuffer,
            error: &conversionError
        ) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return sourceBuffer
        }

        if conversionError == nil,
           convertedBuffer.frameLength > 0 {
            inputContinuation.yield(
                AnalyzerInput(buffer: convertedBuffer)
            )
        }
    }
}
