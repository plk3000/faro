import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import FARO

@MainActor
private final class EvaluationSpeechOutput: SpeechOutputProviding {
    func speak(
        _ text: String,
        language: SupportedLanguage
    ) throws {}

    func stop() {}

    func waitUntilFinished() async {}
}

@MainActor
private final class EvaluationLocationProvider: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus = .denied
    let latestSnapshot: LocationSnapshot? = nil

    func requestAuthorization() async {}
    func start() {}
    func stop() {}
}

struct EvaluationTests {
    private let kitchenID = UUID()
    private let bedroomID = UUID()

    @Test
    func classifiesKnownAndUnknownGroundTruth() {
        let falseConfident = RecognitionEvaluationTrial(
            expectedPlaceID: kitchenID,
            expectedPlaceLabel: "Kitchen",
            angle: .leftOblique,
            lighting: .dimmer,
            language: .englishUS,
            attempt: attempt(
                result: .matched(
                    PlaceMatch(
                        placeID: bedroomID,
                        label: "Bedroom",
                        distance: 0.2,
                        confidence: 0.6
                    )
                ),
                nearestPlaceID: bedroomID,
                nearestLabel: "Bedroom",
                nearestDistance: 0.2
            )
        )
        let correctRejection = RecognitionEvaluationTrial(
            expectedPlaceID: nil,
            expectedPlaceLabel: nil,
            angle: .reverse,
            lighting: .mixed,
            language: .spanishMexico,
            attempt: attempt(
                result: .uncertain,
                nearestPlaceID: kitchenID,
                nearestLabel: "Kitchen",
                nearestDistance: 0.8
            )
        )

        #expect(falseConfident.outcome == .falseConfident)
        #expect(falseConfident.predictedPlaceID == bedroomID)
        #expect(correctRejection.outcome == .correctRejection)
        #expect(correctRejection.predictedPlaceID == nil)
        #expect(correctRejection.nearestPlaceID == kitchenID)
    }

    @Test
    func summarizesAccuracyLatencyAndEvaluationDimensions() {
        let trials = [
            trial(
                expectedPlaceID: kitchenID,
                expectedLabel: "Kitchen",
                result: .matched(
                    PlaceMatch(
                        placeID: kitchenID,
                        label: "Kitchen",
                        distance: 0.1,
                        confidence: 0.8
                    )
                ),
                angle: .enrollmentLike,
                lighting: .similar,
                language: .englishUS,
                latency: 100
            ),
            trial(
                expectedPlaceID: kitchenID,
                expectedLabel: "Kitchen",
                result: .uncertain,
                angle: .leftOblique,
                lighting: .dimmer,
                language: .englishUS,
                latency: 200
            ),
            trial(
                expectedPlaceID: nil,
                expectedLabel: nil,
                result: .matched(
                    PlaceMatch(
                        placeID: bedroomID,
                        label: "Bedroom",
                        distance: 0.2,
                        confidence: 0.6
                    )
                ),
                angle: .rightOblique,
                lighting: .artificial,
                language: .spanishMexico,
                latency: 300
            ),
            trial(
                expectedPlaceID: nil,
                expectedLabel: nil,
                result: .uncertain,
                angle: .reverse,
                lighting: .mixed,
                language: .spanishMexico,
                latency: 400
            )
        ]
        let dataset = EvaluationDataset(
            schemaVersion: EvaluationDataset.currentSchemaVersion,
            recognitionTrials: trials,
            fieldObservations: []
        )

        let summary = EvaluationSummary(dataset: dataset)

        #expect(summary.overall.trialCount == 4)
        #expect(summary.overall.correctMatchCount == 1)
        #expect(summary.overall.correctRejectionCount == 1)
        #expect(summary.overall.uncertainKnownPlaceCount == 1)
        #expect(summary.overall.falseConfidentCount == 1)
        #expect(summary.overall.accuracy == 0.5)
        #expect(summary.overall.knownPlaceRecall == 0.5)
        #expect(summary.overall.unknownPlaceRejectionRate == 0.5)
        #expect(summary.overall.falseConfidentRate == 0.25)
        #expect(summary.overall.averageLatencyMilliseconds == 250)
        #expect(summary.overall.percentile95LatencyMilliseconds == 400)
        #expect(
            summary.byAngle.first {
                $0.value == RecognitionEvaluationAngle.leftOblique.rawValue
            }?.metrics.trialCount == 1
        )
        #expect(
            summary.byLighting.first {
                $0.value
                    == RecognitionEvaluationLighting.artificial.rawValue
            }?.metrics.falseConfidentCount == 1
        )
        #expect(
            summary.byLanguage.first {
                $0.value == SupportedLanguage.spanishMexico.rawValue
            }?.metrics.trialCount == 2
        )
    }

    @Test
    func persistsAndExportsVersionedEvaluationReport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let records = root.appendingPathComponent(
            "records",
            isDirectory: true
        )
        let exports = root.appendingPathComponent(
            "exports",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = EvaluationStore(
            directoryURL: records,
            exportDirectoryURL: exports
        )
        let trial = trial(
            expectedPlaceID: kitchenID,
            expectedLabel: "Kitchen",
            result: .matched(
                PlaceMatch(
                    placeID: kitchenID,
                    label: "Kitchen",
                    distance: 0.1,
                    confidence: 0.8
                )
            ),
            angle: .enrollmentLike,
            lighting: .similar,
            language: .englishUS,
            latency: 125
        )
        let observation = FieldEvaluationObservation(
            category: .proximityAlert,
            language: .spanishMexico,
            usefulnessRating: 4,
            annoyanceRating: 2,
            notes: "Useful at this distance.",
            measuredDistanceCentimeters: 75,
            telemetryDistanceMillimeters: 740,
            telemetryWarningState: .fast,
            telemetryOperatingMode: .navigating,
            alertHeard: true
        )

        _ = try await store.append(trial)
        let dataset = try await store.append(observation)

        let reloadedStore = EvaluationStore(
            directoryURL: records,
            exportDirectoryURL: exports
        )
        let reloaded = try await reloadedStore.load()
        #expect(reloaded.schemaVersion == dataset.schemaVersion)
        #expect(reloaded.recognitionTrials.count == 1)
        #expect(reloaded.recognitionTrials.first?.id == trial.id)
        #expect(reloaded.recognitionTrials.first?.outcome == trial.outcome)
        #expect(reloaded.fieldObservations.count == 1)
        #expect(reloaded.fieldObservations.first?.id == observation.id)

        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let exportURL = try await reloadedStore.export(
            generatedAt: generatedAt
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(
            EvaluationExport.self,
            from: Data(contentsOf: exportURL)
        )

        #expect(report.schemaVersion == 1)
        #expect(report.generatedAt == generatedAt)
        #expect(
            report.latencyScope
                == "camera_capture_through_embedding_and_match"
        )
        #expect(report.summary.overall.trialCount == 1)
        #expect(report.summary.fieldObservationCount == 1)
        #expect(report.recognitionTrials.first?.id == trial.id)
        #expect(report.recognitionTrials.first?.outcome == trial.outcome)
        #expect(report.fieldObservations.first?.id == observation.id)
        #expect(
            report.fieldObservations.first?.telemetryWarningState
                == .fast
        )
        #expect(
            report.fieldObservations.first?.expectedWarningState
                == .fast
        )
        #expect(
            report.fieldObservations.first?.telemetryOperatingMode
                == .navigating
        )
        #expect(
            report.configuration.proximityFastMinimumMillimeters
                == 500
        )

        let cleared = try await reloadedStore.clear()
        #expect(cleared == .empty)
        #expect(!FileManager.default.fileExists(atPath: exportURL.path))
    }

    @Test
    @MainActor
    func recognitionRunProducesExportableSummary() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: Place.self,
            PlaceSnapshot.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let captureModel = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a", "kitchen-a"]
            ),
            imageStore: ImageStore(
                directoryURL: root.appendingPathComponent(
                    "images",
                    isDirectory: true
                )
            ),
            sceneDescriber: MockSceneDescriber(delayNanoseconds: 0),
            speechOutput: EvaluationSpeechOutput(),
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: EvaluationLocationProvider()
        )
        let enrolledPlace = await captureModel.capturePlaceView(
            label: "Kitchen",
            into: nil,
            modelContext: context,
            language: .englishUS
        )
        let place = try #require(enrolledPlace)
        let viewModel = EvaluationViewModel(
            store: EvaluationStore(
                directoryURL: root.appendingPathComponent(
                    "evaluation",
                    isDirectory: true
                ),
                exportDirectoryURL: root.appendingPathComponent(
                    "exports",
                    isDirectory: true
                )
            )
        )

        await viewModel.runRecognitionTrial(
            expectedPlace: place,
            angle: .rightOblique,
            lighting: .brighter,
            language: .englishUS,
            places: [place],
            modelContext: context,
            captureModel: captureModel
        )

        #expect(viewModel.dataset.recognitionTrials.count == 1)
        #expect(
            viewModel.dataset.recognitionTrials.first?.outcome
                == .correctMatch
        )
        let exportURL = try #require(viewModel.exportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(
            EvaluationExport.self,
            from: Data(contentsOf: exportURL)
        )
        #expect(report.summary.overall.trialCount == 1)
        #expect(report.summary.overall.accuracy == 1)
        #expect(
            report.summary.byAngle.first {
                $0.value
                    == RecognitionEvaluationAngle.rightOblique.rawValue
            }?.metrics.correctMatchCount == 1
        )
    }

    private func trial(
        expectedPlaceID: UUID?,
        expectedLabel: String?,
        result: PlaceMatchResult,
        angle: RecognitionEvaluationAngle,
        lighting: RecognitionEvaluationLighting,
        language: SupportedLanguage,
        latency: Int
    ) -> RecognitionEvaluationTrial {
        RecognitionEvaluationTrial(
            expectedPlaceID: expectedPlaceID,
            expectedPlaceLabel: expectedLabel,
            angle: angle,
            lighting: lighting,
            language: language,
            attempt: attempt(
                result: result,
                nearestPlaceID: {
                    guard case let .matched(match) = result else {
                        return kitchenID
                    }
                    return match.placeID
                }(),
                nearestLabel: {
                    guard case let .matched(match) = result else {
                        return "Kitchen"
                    }
                    return match.label
                }(),
                nearestDistance: {
                    guard case let .matched(match) = result else {
                        return 0.8
                    }
                    return match.distance
                }(),
                latency: latency
            )
        )
    }

    private func attempt(
        result: PlaceMatchResult,
        nearestPlaceID: UUID?,
        nearestLabel: String?,
        nearestDistance: Double?,
        latency: Int = 100
    ) -> PlaceRecognitionAttempt {
        PlaceRecognitionAttempt(
            evaluation: PlaceMatchEvaluation(
                result: result,
                nearestPlaceID: nearestPlaceID,
                nearestLabel: nearestLabel,
                nearestDistance: nearestDistance,
                nearestCompetingDistance: 0.9,
                candidateCount: 2,
                snapshotCount: 4,
                policy: PlaceMatchingPolicy(
                    maximumDistance: 0.5,
                    minimumSeparation: 0.05
                )
            ),
            modelIdentifier: VisionFeaturePrintEmbedder.identifier,
            latencyMilliseconds: latency
        )
    }
}
