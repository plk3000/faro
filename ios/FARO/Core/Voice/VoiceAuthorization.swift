@preconcurrency import AVFoundation
@preconcurrency import Speech

@MainActor
enum VoiceAuthorization {
    static func requireSpeechRecognition() async throws {
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

    static func requireMicrophone() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard granted else {
            throw SpeechRecognitionError.microphonePermissionDenied
        }
    }
}
