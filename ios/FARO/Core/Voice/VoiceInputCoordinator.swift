@MainActor
protocol VoiceInputCameraControlling: AnyObject {
    func suspendCameraCaptureForVoiceInput() async

    func resumeCameraCaptureAfterVoiceInput(
        language: SupportedLanguage
    ) async -> Bool
}

extension CaptureViewModel: VoiceInputCameraControlling {}

@MainActor
protocol VoiceCommandSessionControlling: AnyObject {
    func beginListening(
        language: SupportedLanguage
    ) async -> Bool

    func finishListening(
        language: SupportedLanguage
    ) async -> VoiceCommand?

    func finishListeningAfterSpeechEndpoint(
        language: SupportedLanguage,
        onSpeechEndpoint: @MainActor () -> Void
    ) async -> VoiceCommand?

    func cancel()
}

extension VoiceCommandViewModel: VoiceCommandSessionControlling {}

@MainActor
struct VoiceInputCoordinator {
    let camera: any VoiceInputCameraControlling
    let voiceSession: any VoiceCommandSessionControlling

    @discardableResult
    func begin(language: SupportedLanguage) async -> Bool {
        await camera.suspendCameraCaptureForVoiceInput()
        guard !Task.isCancelled else {
            _ = await camera.resumeCameraCaptureAfterVoiceInput(
                language: language
            )
            return false
        }

        let started = await voiceSession.beginListening(
            language: language
        )
        guard !Task.isCancelled else {
            voiceSession.cancel()
            _ = await camera.resumeCameraCaptureAfterVoiceInput(
                language: language
            )
            return false
        }
        if !started {
            _ = await camera.resumeCameraCaptureAfterVoiceInput(
                language: language
            )
        }
        return started
    }

    func finish(
        language: SupportedLanguage
    ) async -> VoiceCommand? {
        let command = await voiceSession.finishListening(
            language: language
        )
        let cameraReady = await camera.resumeCameraCaptureAfterVoiceInput(
            language: language
        )
        guard !Task.isCancelled else {
            return nil
        }
        return cameraReady ? command : nil
    }

    func finishAutomatically(
        language: SupportedLanguage,
        onSpeechEndpoint: @MainActor () -> Void = {}
    ) async -> VoiceCommand? {
        let command =
            await voiceSession.finishListeningAfterSpeechEndpoint(
                language: language,
                onSpeechEndpoint: onSpeechEndpoint
            )
        let cameraReady =
            await camera.resumeCameraCaptureAfterVoiceInput(
                language: language
            )
        guard !Task.isCancelled else {
            return nil
        }
        return cameraReady ? command : nil
    }
}
