import SwiftData

enum VoiceCommandExecutionResult {
    case completed
}

@MainActor
struct VoiceCommandExecutor {
    let captureModel: CaptureViewModel
    let modeController: OperatingModeController
    let placeScanConfiguration: PlaceScanConfiguration

    init(
        captureModel: CaptureViewModel,
        modeController: OperatingModeController,
        placeScanConfiguration: PlaceScanConfiguration = .voiceEnrollment
    ) {
        self.captureModel = captureModel
        self.modeController = modeController
        self.placeScanConfiguration = placeScanConfiguration
    }

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
            await captureModel.preparePlaceMemoryLocation()
            try Task.checkCancellation()
            await captureModel.recognizePlace(
                in: places,
                modelContext: modelContext,
                language: language
            )
            return .completed

        case let .rememberPlace(label):
            await captureModel.preparePlaceMemoryLocation()
            try Task.checkCancellation()
            await captureModel.capturePlaceScan(
                label: label,
                into: nil,
                modelContext: modelContext,
                language: language,
                configuration: placeScanConfiguration
            )
            return .completed

        case .whatIsAhead:
            try requireNavigating()
            await captureModel.describe(language: language)
            return .completed

        case .startNavigating:
            modeController.transition(
                to: .navigating,
                language: language
            )
            return .completed

        case .stopNavigating:
            captureModel.stopNavigationOutput()
            modeController.transition(
                to: .inactive,
                language: language
            )
            return .completed
        }
    }

    private func requireNavigating() throws {
        guard modeController.navigationOutputEnabled else {
            throw VoiceCommandError.navigatingModeRequired
        }
    }
}
