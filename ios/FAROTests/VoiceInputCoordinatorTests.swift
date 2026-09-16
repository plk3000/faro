import Testing
@testable import FARO

@MainActor
private final class RecordingVoiceCamera:
    VoiceInputCameraControlling
{
    let events: EventLog
    var resumeResult = true

    init(events: EventLog) {
        self.events = events
    }

    func pauseCameraForVoiceInput() async {
        events.values.append("camera.pause")
    }

    func resumeCameraAfterVoiceInput(
        language: SupportedLanguage
    ) async -> Bool {
        events.values.append("camera.resume.\(language.rawValue)")
        return resumeResult
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
}

@MainActor
private final class EventLog {
    var values: [String] = []
}

@MainActor
struct VoiceInputCoordinatorTests {
    @Test
    func cameraStopsBeforeMicrophoneStarts() async {
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
                "camera.pause",
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
                "camera.pause",
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
}
