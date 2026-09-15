import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import FARO

@MainActor
private final class FixedLocationProvider: LocationProviding {
    let authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    let latestSnapshot: LocationSnapshot?

    init(snapshot: LocationSnapshot? = nil) {
        latestSnapshot = snapshot
    }

    func requestAuthorization() {}
    func start() {}
    func stop() {}
}

@MainActor
struct PlaceWorkflowTests {
    @Test(arguments: SupportedLanguage.allCases)
    func enrollsAndRecognizesWithoutTranslatingTheLabel(
        language: SupportedLanguage
    ) async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let speech = RecordingSpeechOutput()
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: [
                    "kitchen-a",
                    "kitchen-b",
                    "kitchen-a"
                ]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            sceneDescriber: MockSceneDescriber(delayNanoseconds: 0),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )
        let label = "Cocina de José"

        var place = await model.capturePlaceView(
            label: label,
            into: nil,
            modelContext: resources.context,
            language: language
        )
        place = await model.capturePlaceView(
            label: "This edit must not rename the place",
            into: place,
            modelContext: resources.context,
            language: language
        )

        #expect(place?.label == label)
        #expect(place?.snapshots.count == 2)
        #expect(place?.snapshots.allSatisfy {
            !$0.imageFilename.isEmpty
                && $0.embeddingComponentCount == 256
        } == true)

        await model.recognizePlace(
            in: place.map { [$0] } ?? [],
            language: language
        )

        let expected = language.text(
            .placeMatched,
            argument: label
        )
        #expect(model.latestPlaceResult?.text == expected)
        #expect(model.latestPlaceResult?.language == language)
        #expect(speech.spoken.last?.text == expected)
        #expect(speech.spoken.last?.language == language)
    }

    @Test
    func storesLocationWhenAvailable() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let location = LocationSnapshot(
            latitude: 47.6,
            longitude: -122.3,
            horizontalAccuracy: 25,
            headingDegrees: 90
        )
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a"]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: RecordingSpeechOutput(),
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider(snapshot: location)
        )

        let place = await model.capturePlaceView(
            label: "Kitchen",
            into: nil,
            modelContext: resources.context,
            language: .englishUS
        )

        #expect(place?.snapshots.first?.locationSnapshot == location)
    }

    @Test
    func enrollmentSucceedsWithoutLocation() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a"]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: RecordingSpeechOutput(),
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )

        let place = await model.capturePlaceView(
            label: "Kitchen",
            into: nil,
            modelContext: resources.context,
            language: .englishUS
        )

        #expect(place?.snapshots.count == 1)
        #expect(place?.snapshots.first?.locationSnapshot == nil)
    }

    @Test
    func corruptedSnapshotDoesNotBlockValidPlaceRecognition() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let speech = RecordingSpeechOutput()
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a", "kitchen-a"]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )
        let validPlace = try #require(
            await model.capturePlaceView(
                label: "Kitchen",
                into: nil,
                modelContext: resources.context,
                language: .englishUS
            )
        )
        let corruptedPlace = Place(label: "Corrupted")
        corruptedPlace.snapshots.append(
            PlaceSnapshot(
                imageFilename: "missing.jpg",
                embeddingData: Data(),
                embeddingModel: PixelGridEmbedder.identifier,
                embeddingComponentType:
                    ImageEmbedding.ComponentType.float32.rawValue,
                embeddingComponentCount: 0
            )
        )
        resources.context.insert(corruptedPlace)
        try resources.context.save()

        await model.recognizePlace(
            in: [corruptedPlace, validPlace],
            language: .englishUS
        )

        #expect(model.latestPlaceResult?.text == "You are in Kitchen.")
        #expect(speech.spoken.last?.text == "You are in Kitchen.")
    }

    @Test
    func renameAndDeleteUpdatePersistenceAndStoredImages() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a"]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: RecordingSpeechOutput(),
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )
        let place = try #require(
            await model.capturePlaceView(
                label: "Kitchen",
                into: nil,
                modelContext: resources.context,
                language: .englishUS
            )
        )
        let filename = try #require(
            place.snapshots.first?.imageFilename
        )

        try model.rename(
            place,
            to: "  Cocina principal  ",
            modelContext: resources.context
        )
        #expect(place.label == "Cocina principal")

        try await model.delete(
            place,
            modelContext: resources.context
        )

        let places = try resources.context.fetch(
            FetchDescriptor<Place>()
        )
        #expect(places.isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: resources.directory
                    .appendingPathComponent(filename)
                    .path
            )
        )
    }

    @Test(arguments: SupportedLanguage.allCases)
    func reportsNoSavedPlacesInTheSelectedLanguage(
        language: SupportedLanguage
    ) async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let speech = RecordingSpeechOutput()
        let model = CaptureViewModel(
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )

        await model.recognizePlace(in: [], language: language)

        let expected = PlaceWorkflowError.noRememberedPlaces
            .appMessage
            .localized(in: language)
        #expect(model.statusText(language: language) == expected)
        #expect(speech.spoken.last?.text == expected)
        #expect(speech.spoken.last?.language == language)
    }

    private func makeResources() throws -> (
        directory: URL,
        context: ModelContext
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: Place.self,
            PlaceSnapshot.self,
            configurations: configuration
        )
        return (directory, ModelContext(container))
    }
}
