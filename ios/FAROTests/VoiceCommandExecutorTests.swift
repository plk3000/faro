import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import FARO

@MainActor
private final class VoiceCommandLocationProvider: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    let latestSnapshot: LocationSnapshot? = nil

    func requestAuthorization() async {}
    func start() {}
    func stop() {}
}

@MainActor
private final class SilentModeFeedback: ModeFeedbackProviding {
    func confirmTransition(
        to mode: OperatingMode,
        language: SupportedLanguage
    ) {}
}

@MainActor
struct VoiceCommandExecutorTests {
    @Test(arguments: SupportedLanguage.allCases)
    func routesEveryCommandAndPreservesLanguage(
        language: SupportedLanguage
    ) async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let speech = RecordingSpeechOutput()
        let captureModel = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: [
                    "kitchen-a",
                    "kitchen-a",
                    "kitchen-a",
                    "kitchen-a"
                ]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            sceneDescriber: MockSceneDescriber(delayNanoseconds: 0),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: VoiceCommandLocationProvider()
        )
        let modeController = OperatingModeController(
            feedback: SilentModeFeedback()
        )
        let executor = VoiceCommandExecutor(
            captureModel: captureModel,
            modeController: modeController,
            placeScanConfiguration: PlaceScanConfiguration(
                viewCount: 9,
                initialCaptureDelay: .zero,
                captureInterval: .zero
            )
        )

        _ = try await executor.execute(
            .describeScene,
            places: [],
            modelContext: resources.context,
            language: language
        )
        #expect(captureModel.latestDescription?.language == language)

        _ = try await executor.execute(
            .rememberPlace(label: "Cocina de José"),
            places: [],
            modelContext: resources.context,
            language: language
        )
        let savedPlaces = try resources.context.fetch(
            FetchDescriptor<Place>()
        )
        let place = try #require(savedPlaces.first)
        #expect(place.label == "Cocina de José")
        #expect(place.snapshots.count == 9)
        #expect(
            speech.spoken.contains(
                .init(
                    text: language.text(
                        .placeScanInstructions,
                        arguments: ["9", "Cocina de José"]
                    ),
                    language: language
                )
            )
        )
        #expect(
            speech.spoken.contains(
                .init(
                    text: language.text(
                        .statusPlaceScanComplete,
                        arguments: ["Cocina de José", "9"]
                    ),
                    language: language
                )
            )
        )

        _ = try await executor.execute(
            .startNavigating,
            places: [place],
            modelContext: resources.context,
            language: language
        )
        #expect(modeController.currentMode == .navigating)

        _ = try await executor.execute(
            .whereAmI,
            places: [place],
            modelContext: resources.context,
            language: language
        )
        #expect(captureModel.latestPlaceResult?.language == language)
        #expect(
            captureModel.latestPlaceResult?.text
                == language.text(
                    .placeMatched,
                    argument: "Cocina de José"
                )
        )

        _ = try await executor.execute(
            .whatIsAhead,
            places: [place],
            modelContext: resources.context,
            language: language
        )
        #expect(captureModel.latestDescription?.language == language)
        #expect(speech.spoken.last?.language == language)

        _ = try await executor.execute(
            .stopNavigating,
            places: [place],
            modelContext: resources.context,
            language: language
        )
        #expect(modeController.currentMode == .inactive)
    }

    @Test(arguments: [
        VoiceCommand.whereAmI,
        VoiceCommand.whatIsAhead
    ])
    func navigationCommandsRequireNavigating(
        command: VoiceCommand
    ) async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let executor = VoiceCommandExecutor(
            captureModel: CaptureViewModel(
                imageStore: ImageStore(
                    directoryURL: resources.directory
                ),
                speechOutput: RecordingSpeechOutput(),
                imageEmbedder: PixelGridEmbedder(),
                locationProvider: VoiceCommandLocationProvider()
            ),
            modeController: OperatingModeController(
                feedback: SilentModeFeedback()
            )
        )

        do {
            _ = try await executor.execute(
                command,
                places: [],
                modelContext: resources.context,
                language: .englishUS
            )
            Issue.record("Expected Navigating mode to be required")
        } catch {
            #expect(
                error as? VoiceCommandError
                    == .navigatingModeRequired
            )
        }
    }

    private func makeResources() throws -> (
        directory: URL,
        context: ModelContext
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let container = try ModelContainer(
            for: Place.self,
            PlaceSnapshot.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true
            )
        )
        return (directory, ModelContext(container))
    }
}
