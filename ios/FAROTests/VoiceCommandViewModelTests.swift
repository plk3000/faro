import Testing
@testable import FARO

@MainActor
private final class StubSpeechRecognizer: SpeechRecognizing {
    var partialTranscript = ""
    var finalTranscript = ""
    var startError: (any Error)?
    var stopError: (any Error)?
    private(set) var startedLanguages: [SupportedLanguage] = []
    private(set) var cancelCount = 0
    private(set) var endpointWaitCount = 0

    func start(
        language: SupportedLanguage,
        onTranscript: @escaping @MainActor (String) -> Void
    ) async throws {
        if let startError {
            throw startError
        }
        startedLanguages.append(language)
        if !partialTranscript.isEmpty {
            onTranscript(partialTranscript)
        }
    }

    func waitForSpeechEndpoint() async throws {
        endpointWaitCount += 1
    }

    func stop() async throws -> String {
        if let stopError {
            throw stopError
        }
        return finalTranscript
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class RecordingVoiceCommandFeedback:
    VoiceCommandFeedbackProviding
{
    struct Event: Equatable {
        let message: String
        let language: SupportedLanguage
    }

    private(set) var events: [Event] = []

    func announceFailure(
        _ message: String,
        language: SupportedLanguage
    ) {
        events.append(Event(message: message, language: language))
    }
}

@MainActor
struct VoiceCommandViewModelTests {
    @Test(arguments: [
        (
            SupportedLanguage.englishUS,
            "Where am I?",
            VoiceCommand.whereAmI
        ),
        (
            SupportedLanguage.spanishMexico,
            "¿Qué hay delante?",
            VoiceCommand.whatIsAhead
        )
    ])
    func recordsAndParsesUsingTheSelectedLanguage(
        language: SupportedLanguage,
        transcript: String,
        expected: VoiceCommand
    ) async {
        let recognizer = StubSpeechRecognizer()
        recognizer.partialTranscript = transcript
        recognizer.finalTranscript = transcript
        let model = VoiceCommandViewModel(
            recognizer: recognizer,
            feedback: RecordingVoiceCommandFeedback()
        )

        await model.beginListening(language: language)
        #expect(model.isListening)
        #expect(model.transcript == transcript)

        let command = await model.finishListening(
            language: language
        )

        #expect(command == expected)
        #expect(recognizer.startedLanguages == [language])
        #expect(!model.isListening)
        #expect(model.errorMessage == nil)
    }

    @Test(arguments: SupportedLanguage.allCases)
    func presentsRecognitionErrorsInTheSelectedLanguage(
        language: SupportedLanguage
    ) async {
        let recognizer = StubSpeechRecognizer()
        recognizer.startError =
            SpeechRecognitionError.microphonePermissionDenied
        let feedback = RecordingVoiceCommandFeedback()
        let model = VoiceCommandViewModel(
            recognizer: recognizer,
            feedback: feedback
        )

        await model.beginListening(language: language)

        let expected = language.text(.errorMicrophonePermission)
        #expect(model.errorText(language: language) == expected)
        #expect(
            feedback.events == [
                .init(message: expected, language: language)
            ]
        )
    }

    @Test(arguments: SupportedLanguage.allCases)
    func reportsUnrecognizedCommands(
        language: SupportedLanguage
    ) async {
        let recognizer = StubSpeechRecognizer()
        recognizer.finalTranscript = "Turn on the lights"
        let feedback = RecordingVoiceCommandFeedback()
        let model = VoiceCommandViewModel(
            recognizer: recognizer,
            feedback: feedback
        )

        await model.beginListening(language: language)
        let command = await model.finishListening(
            language: language
        )

        let expected = language.text(.errorVoiceCommandUnrecognized)
        #expect(command == nil)
        #expect(model.errorText(language: language) == expected)
        #expect(feedback.events.last?.message == expected)
    }

    @Test(arguments: SupportedLanguage.allCases)
    func automaticRecordingWaitsForSpeechEndpoint(
        language: SupportedLanguage
    ) async {
        let recognizer = StubSpeechRecognizer()
        recognizer.finalTranscript = language == .englishUS
            ? "describe"
            : "describe"
        let model = VoiceCommandViewModel(
            recognizer: recognizer,
            feedback: RecordingVoiceCommandFeedback()
        )

        await model.beginListening(language: language)
        let command = await model.finishListeningAfterSpeechEndpoint(
            language: language
        )

        #expect(command == .describeScene)
        #expect(recognizer.endpointWaitCount == 1)
    }
}
