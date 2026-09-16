@MainActor
protocol VoiceInputCameraControlling: AnyObject {
    func pauseCameraForVoiceInput() async

    func resumeCameraAfterVoiceInput(
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
}

extension VoiceCommandViewModel: VoiceCommandSessionControlling {}

@MainActor
struct VoiceInputCoordinator {
    let camera: any VoiceInputCameraControlling
    let voiceSession: any VoiceCommandSessionControlling

    @discardableResult
    func begin(language: SupportedLanguage) async -> Bool {
        await camera.pauseCameraForVoiceInput()
        let started = await voiceSession.beginListening(
            language: language
        )
        if !started {
            _ = await camera.resumeCameraAfterVoiceInput(
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
        let cameraReady = await camera.resumeCameraAfterVoiceInput(
            language: language
        )
        return cameraReady ? command : nil
    }
}
