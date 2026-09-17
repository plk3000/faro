@preconcurrency import AVFoundation
@preconcurrency import Speech

@MainActor
enum VoiceAuthorization {
    static func requireSpeechRecognition() async throws {
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        guard status == .authorized else {
            throw SpeechRecognitionError.speechPermissionDenied
        }
    }

    static func requireMicrophone() async throws {
        try Task.checkCancellation()
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        try Task.checkCancellation()
        guard granted else {
            throw SpeechRecognitionError.microphonePermissionDenied
        }
    }
}
