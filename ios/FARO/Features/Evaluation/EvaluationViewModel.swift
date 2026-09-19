import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class EvaluationViewModel {
    @ObservationIgnored
    private let store: EvaluationStore

    private(set) var dataset: EvaluationDataset = .empty
    private(set) var latestTrial: RecognitionEvaluationTrial?
    private(set) var exportURL: URL?
    private(set) var errorMessage: AppMessage?
    private(set) var isLoading = false
    private(set) var isRunningRecognition = false
    private(set) var isSavingObservation = false
    private(set) var isClearing = false

    init(store: EvaluationStore = EvaluationStore()) {
        self.store = store
    }

    var summary: EvaluationSummary {
        EvaluationSummary(dataset: dataset)
    }

    var hasRecords: Bool {
        !dataset.recognitionTrials.isEmpty
            || !dataset.fieldObservations.isEmpty
    }

    func load() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            dataset = try await store.load()
            try await refreshExport()
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    func runRecognitionTrial(
        expectedPlace: Place?,
        angle: RecognitionEvaluationAngle,
        lighting: RecognitionEvaluationLighting,
        language: SupportedLanguage,
        places: [Place],
        modelContext: ModelContext,
        captureModel: CaptureViewModel
    ) async {
        guard !isRunningRecognition else {
            return
        }
        guard !places.isEmpty else {
            errorMessage = AppMessage(.errorNoRememberedPlaces)
            return
        }

        isRunningRecognition = true
        errorMessage = nil
        defer { isRunningRecognition = false }

        await captureModel.preparePlaceMemoryLocation()
        guard !Task.isCancelled else {
            return
        }
        guard let attempt = await captureModel.recognizePlace(
            in: places,
            modelContext: modelContext,
            language: language,
            speakResult: false,
            publishResult: false
        ) else {
            errorMessage = captureModel.errorMessage
                ?? AppMessage(.errorEvaluationRecognition)
            return
        }
        guard !Task.isCancelled else {
            return
        }

        let trial = RecognitionEvaluationTrial(
            expectedPlaceID: expectedPlace?.id,
            expectedPlaceLabel: expectedPlace?.label,
            angle: angle,
            lighting: lighting,
            language: language,
            attempt: attempt
        )

        do {
            dataset = try await store.append(trial)
            latestTrial = trial
            try await refreshExport()
        } catch {
            report(error)
        }
    }

    func saveObservation(
        category: FieldObservationCategory,
        language: SupportedLanguage,
        usefulnessRating: Int,
        annoyanceRating: Int,
        notes: String,
        measuredDistanceCentimeters: Double?,
        alertHeard: Bool,
        telemetry: ObstacleTelemetry?
    ) async {
        guard !isSavingObservation else {
            return
        }
        if let measuredDistanceCentimeters,
           measuredDistanceCentimeters < 0 {
            errorMessage = AppMessage(.errorEvaluationDistance)
            return
        }

        isSavingObservation = true
        errorMessage = nil
        defer { isSavingObservation = false }

        let isProximity = category == .proximityAlert
        let observation = FieldEvaluationObservation(
            category: category,
            language: language,
            usefulnessRating: usefulnessRating,
            annoyanceRating: annoyanceRating,
            notes: notes.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            measuredDistanceCentimeters: isProximity
                ? measuredDistanceCentimeters
                : nil,
            telemetryDistanceMillimeters: isProximity
                ? telemetry?.distanceMillimeters
                : nil,
            telemetryWarningState: isProximity
                ? telemetry?.warningState
                : nil,
            telemetryOperatingMode: isProximity
                ? telemetry?.operatingMode
                : nil,
            alertHeard: isProximity ? alertHeard : nil
        )

        do {
            dataset = try await store.append(observation)
            try await refreshExport()
        } catch {
            report(error)
        }
    }

    func clearAll() async {
        guard !isClearing else {
            return
        }
        isClearing = true
        errorMessage = nil
        defer { isClearing = false }

        do {
            dataset = try await store.clear()
            latestTrial = nil
            exportURL = nil
        } catch {
            report(error)
        }
    }

    func errorText(language: SupportedLanguage) -> String? {
        errorMessage?.localized(in: language)
    }

    private func refreshExport() async throws {
        exportURL = hasRecords ? try await store.export() : nil
    }

    private func report(_ error: any Error) {
        errorMessage = (error as? any AppMessageProviding)?.appMessage
            ?? AppMessage(.errorGenericAction)
    }
}
