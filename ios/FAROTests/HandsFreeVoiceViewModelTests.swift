import Testing
@testable import FARO

@MainActor
private final class StubWakePhraseDetector: WakePhraseDetecting {
    var startErrors: [any Error] = []
    private(set) var startedLanguages: [SupportedLanguage] = []
    private(set) var stopCount = 0
    private var wakeHandler: (@MainActor () -> Void)?
    private var failureHandler:
        (@MainActor (any Error) -> Void)?

    func start(
        language: SupportedLanguage,
        onWakePhrase: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws {
        if !startErrors.isEmpty {
            throw startErrors.removeFirst()
        }
        startedLanguages.append(language)
        wakeHandler = onWakePhrase
        failureHandler = onFailure
    }

    func stop() {
        stopCount += 1
        wakeHandler = nil
        failureHandler = nil
    }

    func emitWakePhrase() {
        let handler = wakeHandler
        handler?()
    }

    func emitFailure(_ error: any Error) {
        let handler = failureHandler
        handler?(error)
    }
}

@MainActor
private final class RecordingHandsFreeFeedback:
    HandsFreeFeedbackProviding
{
    private(set) var events: [String] = []
    var holdsWakeConfirmation = false
    private var wakeContinuation:
        CheckedContinuation<Void, Never>?

    func confirmArmed() async {
        events.append("armed")
    }

    func confirmWakePhrase() async {
        events.append("wake-started")
        if holdsWakeConfirmation {
            await withCheckedContinuation { continuation in
                wakeContinuation = continuation
            }
        }
        events.append("wake-finished")
    }

    func finishWakeConfirmation() {
        wakeContinuation?.resume()
        wakeContinuation = nil
    }
}

@MainActor
private final class RecordingHandsFreeFailureFeedback:
    VoiceCommandFeedbackProviding
{
    private(set) var events: [String] = []

    func announceFailure(
        _ message: String,
        language: SupportedLanguage
    ) {
        events.append("\(language.rawValue):\(message)")
    }
}

@MainActor
struct HandsFreeVoiceViewModelTests {
    @Test
    func armsAndEmitsOneWakeEvent() async {
        let detector = StubWakePhraseDetector()
        let feedback = RecordingHandsFreeFeedback()
        let model = HandsFreeVoiceViewModel(
            detector: detector,
            feedback: feedback,
            failureFeedback: RecordingHandsFreeFailureFeedback(),
            configuration: HandsFreeActivationConfiguration(
                retryDelays: [.zero]
            )
        )
        var wakeCount = 0

        let armed = await model.arm(language: .englishUS) {
            wakeCount += 1
        }
        detector.emitWakePhrase()
        detector.emitWakePhrase()
        await waitUntil { wakeCount == 1 }

        #expect(armed)
        #expect(model.state == .wakePhraseDetected)
        #expect(wakeCount == 1)
        #expect(
            feedback.events == [
                "armed",
                "wake-started",
                "wake-finished"
            ]
        )
    }

    @Test
    func startsCommandOnlyAfterWakeFeedbackFinishes() async {
        let detector = StubWakePhraseDetector()
        let feedback = RecordingHandsFreeFeedback()
        feedback.holdsWakeConfirmation = true
        let model = HandsFreeVoiceViewModel(
            detector: detector,
            feedback: feedback,
            failureFeedback: RecordingHandsFreeFailureFeedback(),
            configuration: HandsFreeActivationConfiguration(
                retryDelays: [.zero]
            )
        )
        var wakeCount = 0

        await model.arm(language: .englishUS) {
            wakeCount += 1
        }
        detector.emitWakePhrase()
        await waitUntil {
            feedback.events.contains("wake-started")
        }

        #expect(model.state == .wakePhraseDetected)
        #expect(wakeCount == 0)

        feedback.finishWakeConfirmation()
        await waitUntil { wakeCount == 1 }

        #expect(wakeCount == 1)
        #expect(feedback.events.last == "wake-finished")
    }

    @Test
    func disarmingDuringFeedbackPreventsCommandCapture() async {
        let detector = StubWakePhraseDetector()
        let feedback = RecordingHandsFreeFeedback()
        feedback.holdsWakeConfirmation = true
        let model = HandsFreeVoiceViewModel(
            detector: detector,
            feedback: feedback,
            failureFeedback: RecordingHandsFreeFailureFeedback(),
            configuration: HandsFreeActivationConfiguration(
                retryDelays: [.zero]
            )
        )
        var wakeCount = 0

        await model.arm(language: .englishUS) {
            wakeCount += 1
        }
        detector.emitWakePhrase()
        await waitUntil {
            feedback.events.contains("wake-started")
        }
        model.disarm()
        feedback.finishWakeConfirmation()
        await waitUntil {
            feedback.events.contains("wake-finished")
        }

        #expect(model.state == .disabled)
        #expect(wakeCount == 0)
    }

    @Test
    func retriesTemporaryAudioFailure() async {
        let detector = StubWakePhraseDetector()
        detector.startErrors = [
            SpeechRecognitionError.audioInputUnavailable
        ]
        let model = HandsFreeVoiceViewModel(
            detector: detector,
            feedback: RecordingHandsFreeFeedback(),
            failureFeedback: RecordingHandsFreeFailureFeedback(),
            configuration: HandsFreeActivationConfiguration(
                retryDelays: [.zero, .zero]
            )
        )

        let armed = await model.arm(
            language: .spanishMexico,
            onWakePhrase: {}
        )

        #expect(armed)
        #expect(detector.startedLanguages == [.spanishMexico])
        #expect(model.state == .listeningForWakePhrase)
    }

    @Test
    func permissionFailureDoesNotRetry() async {
        let detector = StubWakePhraseDetector()
        detector.startErrors = [
            SpeechRecognitionError.microphonePermissionDenied,
            SpeechRecognitionError.audioInputUnavailable
        ]
        let feedback = RecordingHandsFreeFailureFeedback()
        let model = HandsFreeVoiceViewModel(
            detector: detector,
            feedback: RecordingHandsFreeFeedback(),
            failureFeedback: feedback,
            configuration: HandsFreeActivationConfiguration(
                retryDelays: [.zero, .zero]
            )
        )

        let armed = await model.arm(
            language: .englishUS,
            onWakePhrase: {}
        )

        #expect(!armed)
        #expect(model.state == .disabled)
        #expect(
            model.errorText(language: .englishUS)
                == SupportedLanguage.englishUS.text(
                    .errorMicrophonePermission
                )
        )
        #expect(feedback.events.count == 1)
    }

    @Test
    func disarmingInvalidatesAStaleWakeCallback() async {
        let detector = StubWakePhraseDetector()
        let model = HandsFreeVoiceViewModel(
            detector: detector,
            feedback: RecordingHandsFreeFeedback(),
            failureFeedback: RecordingHandsFreeFailureFeedback(),
            configuration: HandsFreeActivationConfiguration(
                retryDelays: [.zero]
            )
        )
        var wakeCount = 0

        await model.arm(language: .englishUS) {
            wakeCount += 1
        }
        model.disarm()
        detector.emitWakePhrase()

        #expect(model.state == .disabled)
        #expect(wakeCount == 0)
    }

    @Test
    func runtimeFailureStopsListeningAndReportsTheError() async {
        let detector = StubWakePhraseDetector()
        let failureFeedback = RecordingHandsFreeFailureFeedback()
        let model = HandsFreeVoiceViewModel(
            detector: detector,
            feedback: RecordingHandsFreeFeedback(),
            failureFeedback: failureFeedback,
            configuration: HandsFreeActivationConfiguration(
                retryDelays: [.zero]
            )
        )

        await model.arm(
            language: .spanishMexico,
            onWakePhrase: {}
        )
        detector.emitFailure(
            SpeechRecognitionError.recognitionFailed
        )

        #expect(model.state == .disabled)
        #expect(
            model.errorText(language: .spanishMexico)
                == SupportedLanguage.spanishMexico.text(
                    .errorSpeechRecognition
                )
        )
        #expect(failureFeedback.events.count == 1)
    }

    @Test
    func activationPolicyRequiresForegroundIdleOptIn() {
        #expect(
            HandsFreeActivationPolicy.shouldArm(
                isEnabled: true,
                isSceneActive: true,
                isEnrollmentPresented: false,
                isCaptureBusy: false,
                isVoiceSessionActive: false
            )
        )
        #expect(
            !HandsFreeActivationPolicy.shouldArm(
                isEnabled: false,
                isSceneActive: true,
                isEnrollmentPresented: false,
                isCaptureBusy: false,
                isVoiceSessionActive: false
            )
        )
        #expect(
            !HandsFreeActivationPolicy.shouldArm(
                isEnabled: true,
                isSceneActive: false,
                isEnrollmentPresented: false,
                isCaptureBusy: false,
                isVoiceSessionActive: false
            )
        )
        #expect(
            !HandsFreeActivationPolicy.shouldArm(
                isEnabled: true,
                isSceneActive: true,
                isEnrollmentPresented: true,
                isCaptureBusy: false,
                isVoiceSessionActive: false
            )
        )
        #expect(
            !HandsFreeActivationPolicy.shouldArm(
                isEnabled: true,
                isSceneActive: true,
                isEnrollmentPresented: false,
                isCaptureBusy: true,
                isVoiceSessionActive: false
            )
        )
        #expect(
            !HandsFreeActivationPolicy.shouldArm(
                isEnabled: true,
                isSceneActive: true,
                isEnrollmentPresented: false,
                isCaptureBusy: false,
                isVoiceSessionActive: true
            )
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for asynchronous state")
    }
}
