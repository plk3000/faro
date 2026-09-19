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

    func requestAuthorization() async {}
    func start() {}
    func stop() {}
}

private actor FailingAfterImageSource: ImageSource {
    private let source: FixtureImageSource
    private let successfulCaptureLimit: Int
    private var successfulCaptureCount = 0

    init(
        successfulCaptureLimit: Int,
        resourceNames: [String]
    ) {
        self.successfulCaptureLimit = successfulCaptureLimit
        source = FixtureImageSource(resourceNames: resourceNames)
    }

    func capture() async throws -> CapturedImage {
        guard successfulCaptureCount < successfulCaptureLimit else {
            throw ImageSourceError.captureFailed
        }
        successfulCaptureCount += 1
        return try await source.capture()
    }
}

@MainActor
private final class CancellationAwareSpeechOutput: SpeechOutputProviding {
    private let blockedWaitNumber: Int
    private(set) var spoken: [RecordingSpeechOutput.Entry] = []
    private(set) var stopCount = 0
    private(set) var waitCount = 0
    private(set) var isWaiting = false

    init(blockedWaitNumber: Int) {
        self.blockedWaitNumber = blockedWaitNumber
    }

    func speak(
        _ text: String,
        language: SupportedLanguage
    ) throws {
        spoken.append(.init(text: text, language: language))
    }

    func stop() {
        stopCount += 1
    }

    func waitUntilFinished() async {
        waitCount += 1
        guard waitCount == blockedWaitNumber else {
            return
        }

        isWaiting = true
        defer { isWaiting = false }

        while true {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }
}

private actor CancellationMaskingImageSource: ImageSource {
    private(set) var isCapturing = false

    func capture() async throws -> CapturedImage {
        isCapturing = true
        do {
            try await Task.sleep(for: .seconds(10))
        } catch {
            throw ImageSourceError.captureFailed
        }
        throw ImageSourceError.captureFailed
    }
}

@MainActor
struct PlaceWorkflowTests {
    @Test(arguments: SupportedLanguage.allCases)
    func automaticPlaceScanCapturesNineViewSweep(
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
                    "kitchen-a",
                    "kitchen-b",
                    "kitchen-a"
                ]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )
        let configuration = PlaceScanConfiguration(
            viewCount: 9,
            initialCaptureDelay: .zero,
            captureInterval: .zero
        )

        let place = await model.capturePlaceScan(
            label: "Cocina de José",
            modelContext: resources.context,
            language: language,
            configuration: configuration
        )

        #expect(place?.label == "Cocina de José")
        #expect(place?.snapshots.count == 9)
        #expect(model.storedImages.count == 9)
        #expect(model.errorMessage == nil)
        #expect(
            model.statusText(language: language)
                == language.text(
                    .statusPlaceScanComplete,
                    arguments: ["Cocina de José", "9"]
                )
        )
        #expect(
            speech.spoken == [
                .init(
                    text: language.text(
                        .placeScanInstructions,
                        arguments: ["9", "Cocina de José"]
                    ),
                    language: language
                ),
                .init(
                    text: language.text(
                        .statusPlaceScanComplete,
                        arguments: ["Cocina de José", "9"]
                    ),
                    language: language
                )
            ]
        )
    }

    @Test
    func voiceEnrollmentUsesNinePicturesAcrossAHalfTurn() {
        #expect(PlaceScanConfiguration.voiceEnrollment.viewCount == 9)
        #expect(
            PlaceScanConfiguration.voiceEnrollment.initialCaptureDelay
                == .milliseconds(1_500)
        )
        #expect(
            PlaceScanConfiguration.voiceEnrollment.captureInterval
                == .seconds(1)
        )
    }

    @Test
    func automaticPlaceScanPreservesViewsBeforeCaptureFailure() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let speech = RecordingSpeechOutput()
        let model = CaptureViewModel(
            imageSource: FailingAfterImageSource(
                successfulCaptureLimit: 2,
                resourceNames: ["kitchen-a", "kitchen-b"]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )

        let place = await model.capturePlaceScan(
            label: "Kitchen",
            modelContext: resources.context,
            language: .englishUS,
            configuration: PlaceScanConfiguration(
                viewCount: 5,
                initialCaptureDelay: .zero,
                captureInterval: .zero
            )
        )

        #expect(place?.snapshots.count == 2)
        #expect(model.storedImages.count == 2)
        #expect(
            model.errorText(language: .englishUS)
                == ImageSourceError.captureFailed.appMessage.localized(
                    in: .englishUS
                )
        )
        let savedPlaces = try resources.context.fetch(
            FetchDescriptor<Place>()
        )
        #expect(savedPlaces.count == 1)
        #expect(savedPlaces.first?.snapshots.count == 2)
        #expect(
            speech.spoken.last?.text
                == ImageSourceError.captureFailed.appMessage.localized(
                    in: .englishUS
                )
        )
    }

    @Test
    func cancellingPlaceScanStopsGuidanceBeforeCapturing() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let speech = CancellationAwareSpeechOutput(
            blockedWaitNumber: 1
        )
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a"]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )

        let scanTask = Task { @MainActor in
            _ = await model.capturePlaceScan(
                label: "Kitchen",
                modelContext: resources.context,
                language: .englishUS,
                configuration: PlaceScanConfiguration(
                    viewCount: 5,
                    initialCaptureDelay: .zero,
                    captureInterval: .zero
                )
            )
        }
        while !speech.isWaiting {
            await Task.yield()
        }
        scanTask.cancel()
        scanTask.cancel()
        await scanTask.value

        #expect(speech.stopCount == 1)
        #expect(model.storedImages.isEmpty)
        #expect(
            try resources.context.fetch(
                FetchDescriptor<Place>()
            ).isEmpty
        )
    }

    @Test
    func placeScanRemainsBusyUntilCompletionSpeechFinishes() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let speech = CancellationAwareSpeechOutput(
            blockedWaitNumber: 2
        )
        let model = CaptureViewModel(
            imageSource: FixtureImageSource(
                resourceNames: ["kitchen-a"]
            ),
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )

        let scanTask = Task { @MainActor in
            _ = await model.capturePlaceScan(
                label: "Kitchen",
                modelContext: resources.context,
                language: .englishUS,
                configuration: PlaceScanConfiguration(
                    viewCount: 5,
                    initialCaptureDelay: .zero,
                    captureInterval: .zero
                )
            )
        }
        while !speech.isWaiting {
            await Task.yield()
        }

        #expect(model.isEnrolling)
        #expect(
            try resources.context.fetch(
                FetchDescriptor<Place>()
            ).first?.snapshots.count == 5
        )

        scanTask.cancel()
        await scanTask.value

        #expect(!model.isEnrolling)
        #expect(speech.stopCount == 1)
    }

    @Test
    func taskCancellationOverridesImageSourceFailure() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let source = CancellationMaskingImageSource()
        let speech = RecordingSpeechOutput()
        let model = CaptureViewModel(
            imageSource: source,
            imageStore: ImageStore(directoryURL: resources.directory),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )

        let scanTask = Task { @MainActor in
            _ = await model.capturePlaceScan(
                label: "Kitchen",
                modelContext: resources.context,
                language: .englishUS,
                configuration: PlaceScanConfiguration(
                    viewCount: 5,
                    initialCaptureDelay: .zero,
                    captureInterval: .zero
                )
            )
        }
        while !(await source.isCapturing) {
            await Task.yield()
        }

        scanTask.cancel()
        await scanTask.value

        #expect(model.errorMessage == nil)
        #expect(model.storedImages.isEmpty)
        #expect(
            model.statusText(language: .englishUS)
                == SupportedLanguage.englishUS.text(.statusReady)
        )
        #expect(speech.spoken.count == 1)
    }

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

        let attempt = await model.recognizePlace(
            in: place.map { [$0] } ?? [],
            modelContext: resources.context,
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
        #expect(attempt?.modelIdentifier == PixelGridEmbedder.identifier)
        #expect(attempt?.latencyMilliseconds ?? -1 >= 0)
        guard let attempt,
              case let .matched(match) = attempt.evaluation.result else {
            Issue.record("Expected a structured place match")
            return
        }
        #expect(match.placeID == place?.id)
    }

    @Test
    func evaluationRecognitionDoesNotPublishOrSpeak() async throws {
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
            sceneDescriber: MockSceneDescriber(delayNanoseconds: 0),
            speechOutput: speech,
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )
        let place = await model.capturePlaceView(
            label: "Kitchen",
            into: nil,
            modelContext: resources.context,
            language: .englishUS
        )
        let spokenBeforeTrial = speech.spoken.count

        let attempt = await model.recognizePlace(
            in: place.map { [$0] } ?? [],
            modelContext: resources.context,
            language: .englishUS,
            speakResult: false,
            publishResult: false
        )

        #expect(attempt != nil)
        #expect(model.latestPlaceResult == nil)
        #expect(speech.spoken.count == spokenBeforeTrial)
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
            modelContext: resources.context,
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

    @Test
    func reembedsLegacySnapshotsFromTheirSavedJPEGs() async throws {
        let resources = try makeResources()
        defer {
            try? FileManager.default.removeItem(
                at: resources.directory
            )
        }
        let imageStore = ImageStore(directoryURL: resources.directory)
        let source = FixtureImageSource(
            resourceNames: ["kitchen-a", "kitchen-a"]
        )
        let enrollmentImage = try await source.capture()
        let storedImage = try await imageStore.save(enrollmentImage)
        let place = Place(label: "Kitchen")
        place.snapshots.append(
            PlaceSnapshot(
                imageFilename: storedImage.filename,
                embeddingData: Data(repeating: 0, count: 4),
                embeddingModel: "legacy-embedding",
                embeddingComponentType:
                    ImageEmbedding.ComponentType.float32.rawValue,
                embeddingComponentCount: 1
            )
        )
        resources.context.insert(place)
        try resources.context.save()

        let model = CaptureViewModel(
            imageSource: source,
            imageStore: imageStore,
            speechOutput: RecordingSpeechOutput(),
            imageEmbedder: PixelGridEmbedder(),
            locationProvider: FixedLocationProvider()
        )

        await model.recognizePlace(
            in: [place],
            modelContext: resources.context,
            language: .englishUS
        )

        let migratedSnapshot = try #require(place.snapshots.first)
        #expect(
            migratedSnapshot.embeddingModel
                == PixelGridEmbedder.identifier
        )
        #expect(migratedSnapshot.embeddingComponentCount == 256)
        #expect(migratedSnapshot.embeddingData.count == 1_024)
        #expect(model.latestPlaceResult?.text == "You are in Kitchen.")
    }

    @Test
    func stoppingNavigationStopsSpokenOutput() async throws {
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

        model.stopNavigationOutput()

        #expect(speech.stopCount == 1)
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

        await model.recognizePlace(
            in: [],
            modelContext: resources.context,
            language: language
        )

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
