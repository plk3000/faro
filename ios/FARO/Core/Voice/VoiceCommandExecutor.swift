import SwiftData

enum VoiceCommandExecutionResult {
    case completed
    case continueEnrollment(Place)
}

@MainActor
struct VoiceCommandExecutor {
    let captureModel: CaptureViewModel
    let modeController: OperatingModeController

    func execute(
        _ command: VoiceCommand,
        places: [Place],
        modelContext: ModelContext,
        language: SupportedLanguage
    ) async throws -> VoiceCommandExecutionResult {
        try Task.checkCancellation()

        switch command {
        case .describeScene:
            await captureModel.describe(language: language)
            return .completed

        case .whereAmI:
            try requireNavigating()
            captureModel.preparePlaceMemoryLocation()
            await captureModel.recognizePlace(
                in: places,
                modelContext: modelContext,
                language: language
            )
            return .completed

        case let .rememberPlace(label):
            captureModel.preparePlaceMemoryLocation()
            let place = await captureModel.capturePlaceView(
                label: label,
                into: nil,
                modelContext: modelContext,
                language: language
            )
            if let place {
                return .continueEnrollment(place)
            }
            return .completed

        case .whatIsAhead:
            try requireNavigating()
            await captureModel.describe(language: language)
            return .completed
        }
    }

    private func requireNavigating() throws {
        guard modeController.navigationOutputEnabled else {
            throw VoiceCommandError.navigatingModeRequired
        }
    }
}
