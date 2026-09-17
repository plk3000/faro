import Testing
@testable import FARO

@MainActor
private final class RecordingVoiceCamera:
    VoiceInputCameraControlling
{
    let events: EventLog
    var resumeResult = true
    var suspendUntilCancelled = false
    var resumeUntilCancelled = false
    private(set) var isSuspending = false
    private(set) var isResuming = false

    init(events: EventLog) {
        self.events = events
    }

    func suspendCameraCaptureForVoiceInput() async {
        events.values.append("camera.suspend-capture")
        guard suspendUntilCancelled else {
            return
        }
        isSuspending = true
        defer { isSuspending = false }
        while true {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    func resumeCameraCaptureAfterVoiceInput(
        language: SupportedLanguage
    ) async -> Bool {
        events.values.append("camera.resume.\(language.rawValue)")
        guard resumeUntilCancelled else {
            return resumeResult
        }
        isResuming = true
        defer { isResuming = false }
        while true {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return resumeResult
            }
        }
    }
}

@MainActor
private final class RecordingVoiceSession:
    VoiceCommandSessionControlling
{
    let events: EventLog
    var beginResult = true
    var command: VoiceCommand? = .describeScene

    init(events: EventLog) {
        self.events = events
    }

    func beginListening(
        language: SupportedLanguage
    ) async -> Bool {
        events.values.append("voice.begin.\(language.rawValue)")
        return beginResult
    }

    func finishListening(
        language: SupportedLanguage
    ) async -> VoiceCommand? {
        events.values.append("voice.finish.\(language.rawValue)")
        return command
    }

    func finishListeningAfterSpeechEndpoint(
        language: SupportedLanguage,
        onSpeechEndpoint: @MainActor () -> Void
    ) async -> VoiceCommand? {
        events.values.append(
            "voice.endpoint.\(language.rawValue)"
        )
        onSpeechEndpoint()
        events.values.append(
            "voice.finish-automatically.\(language.rawValue)"
        )
        return command
    }

    func cancel() {
        events.values.append("voice.cancel")
    }
}

@MainActor
private final class EventLog {
    var values: [String] = []
}

@MainActor
struct VoiceInputCoordinatorTests {
    @Test
    func cameraCaptureSuspendsBeforeMicrophoneStarts() async {
        let events = EventLog()
        let coordinator = VoiceInputCoordinator(
            camera: RecordingVoiceCamera(events: events),
            voiceSession: RecordingVoiceSession(events: events)
        )

        let started = await coordinator.begin(
            language: .englishUS
        )

        #expect(started)
        #expect(
            events.values == [
                "camera.suspend-capture",
                "voice.begin.en-US"
            ]
        )
    }

    @Test
    func failedMicrophoneStartRestoresTheCamera() async {
        let events = EventLog()
        let camera = RecordingVoiceCamera(events: events)
        let voice = RecordingVoiceSession(events: events)
        voice.beginResult = false
        let coordinator = VoiceInputCoordinator(
            camera: camera,
            voiceSession: voice
        )

        let started = await coordinator.begin(
            language: .spanishMexico
        )

        #expect(!started)
        #expect(
            events.values == [
                "camera.suspend-capture",
                "voice.begin.es-MX",
                "camera.resume.es-MX"
            ]
        )
    }

    @Test
    func microphoneStopsBeforeCameraRestarts() async {
        let events = EventLog()
        let coordinator = VoiceInputCoordinator(
            camera: RecordingVoiceCamera(events: events),
            voiceSession: RecordingVoiceSession(events: events)
        )

        let command = await coordinator.finish(
            language: .englishUS
        )

        #expect(command == .describeScene)
        #expect(
            events.values == [
                "voice.finish.en-US",
                "camera.resume.en-US"
            ]
        )
    }

    @Test
    func commandDoesNotRunWhenCameraCannotRestart() async {
        let events = EventLog()
        let camera = RecordingVoiceCamera(events: events)
        camera.resumeResult = false
        let coordinator = VoiceInputCoordinator(
            camera: camera,
            voiceSession: RecordingVoiceSession(events: events)
        )

        let command = await coordinator.finish(
            language: .englishUS
        )

        #expect(command == nil)
    }

    @Test
    func automaticEndpointFinishesBeforeCameraCaptureResumes() async {
        let events = EventLog()
        let coordinator = VoiceInputCoordinator(
            camera: RecordingVoiceCamera(events: events),
            voiceSession: RecordingVoiceSession(events: events)
        )

        let command = await coordinator.finishAutomatically(
            language: .spanishMexico
        ) {
            events.values.append("hands-free.processing")
        }

        #expect(command == .describeScene)
        #expect(
            events.values == [
                "voice.endpoint.es-MX",
                "hands-free.processing",
                "voice.finish-automatically.es-MX",
                "camera.resume.es-MX"
            ]
        )
    }

    @Test
    func cancellationAfterCameraSuspensionDoesNotStartMicrophone() async {
        let events = EventLog()
        let camera = RecordingVoiceCamera(events: events)
        camera.suspendUntilCancelled = true
        let coordinator = VoiceInputCoordinator(
            camera: camera,
            voiceSession: RecordingVoiceSession(events: events)
        )
        let task = Task { @MainActor in
            await coordinator.begin(language: .englishUS)
        }
        while !camera.isSuspending {
            await Task.yield()
        }

        task.cancel()
        let started = await task.value

        #expect(!started)
        #expect(
            events.values == [
                "camera.suspend-capture",
                "camera.resume.en-US"
            ]
        )
    }

    @Test
    func cancellationDuringCameraResumeDiscardsCommand() async {
        let events = EventLog()
        let camera = RecordingVoiceCamera(events: events)
        camera.resumeUntilCancelled = true
        let coordinator = VoiceInputCoordinator(
            camera: camera,
            voiceSession: RecordingVoiceSession(events: events)
        )
        let task = Task { @MainActor in
            await coordinator.finish(language: .spanishMexico)
        }
        while !camera.isResuming {
            await Task.yield()
        }

        task.cancel()
        let command = await task.value

        #expect(command == nil)
        #expect(
            events.values == [
                "voice.finish.es-MX",
                "camera.resume.es-MX"
            ]
        )
    }
}
