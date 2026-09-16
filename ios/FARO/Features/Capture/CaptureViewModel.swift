@preconcurrency import AVFoundation
import Foundation
import Observation
import OSLog
import SwiftData

struct PlaceRecognitionOutput: Equatable, Sendable {
    let message: AppMessage
    let language: SupportedLanguage

    var text: String {
        message.localized(in: language)
    }
}

@MainActor
@Observable
final class CaptureViewModel {
    private static let logger = Logger(
        subsystem: "com.jdsolissmith.faro",
        category: "PlaceMemory"
    )

    private let imageSource: any ImageSource
    private let imageStore: ImageStore
    private let feedback: any CaptureFeedbackProviding
    private let cameraSource: CameraImageSource?
    private let sceneDescriber: any SceneDescribing
    private let speechOutput: any SpeechOutputProviding
    private let imageEmbedder: any ImageEmbedder
    private let locationProvider: any LocationProviding
    private let placeMatcher: PlaceMatcher

    private(set) var latestImageData: Data?
    private(set) var latestDescription: SceneDescription?
    private(set) var latestPlaceResult: PlaceRecognitionOutput?
    private(set) var storedImages: [StoredImage] = []
    private(set) var isCapturing = false
    private(set) var isDescribing = false
    private(set) var isRecognizing = false
    private(set) var isEnrolling = false
    private(set) var statusMessage = AppMessage(.statusReady)
    private(set) var errorMessage: AppMessage?

    var cameraSession: AVCaptureSession? {
        cameraSource?.session
    }

    init(
        imageSource: (any ImageSource)? = nil,
        imageStore: ImageStore = ImageStore(),
        feedback: (any CaptureFeedbackProviding)? = nil,
        sceneDescriber: (any SceneDescribing)? = nil,
        speechOutput: (any SpeechOutputProviding)? = nil,
        imageEmbedder: (any ImageEmbedder)? = nil,
        locationProvider: (any LocationProviding)? = nil,
        placeMatcher: PlaceMatcher? = nil
    ) {
        if let imageSource {
            self.imageSource = imageSource
            cameraSource = imageSource as? CameraImageSource
        } else {
#if targetEnvironment(simulator)
            let source = FixtureImageSource()
            self.imageSource = source
            cameraSource = nil
#else
            let source = CameraImageSource()
            self.imageSource = source
            cameraSource = source
#endif
        }
        self.imageStore = imageStore
        self.feedback = feedback ?? CaptureFeedback()
        self.sceneDescriber = sceneDescriber
            ?? SceneDescriberFactory.makeDefault()
        self.speechOutput = speechOutput ?? SpeechOutput()
        let embedder = imageEmbedder ?? ImageEmbedderFactory.makeDefault()
        self.imageEmbedder = embedder
        self.locationProvider = locationProvider ?? LocationProvider()
        self.placeMatcher = placeMatcher
            ?? PlaceMatcher(embedder: embedder)
    }

    func prepare(language: SupportedLanguage) async {
        do {
            if let cameraSource {
                try await cameraSource.prepare()
            }
            locationProvider.start()
            storedImages = try await imageStore.list()
            statusMessage = AppMessage(.statusReady)
            errorMessage = nil
        } catch {
            report(error, language: language)
        }
    }

    func preparePlaceMemoryLocation() {
        locationProvider.requestAuthorization()
        locationProvider.start()
    }

    func capture(language: SupportedLanguage) async {
        guard !isBusy else {
            return
        }

        isCapturing = true
        statusMessage = AppMessage(.statusCapturingImage)
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let image = try await imageSource.capture()
            let storedImage = try await imageStore.save(image)
            latestImageData = try await imageStore.load(storedImage)
            storedImages = try await imageStore.list()
            statusMessage = AppMessage(.statusImageCapturedSaved)
            feedback.announceSuccess(language: language)
        } catch {
            report(error, language: language)
        }
    }

    func describe(language: SupportedLanguage) async {
        guard !isBusy else {
            return
        }

        isDescribing = true
        statusMessage = AppMessage(.statusCapturingScene)
        errorMessage = nil
        latestDescription = nil
        defer { isDescribing = false }

        do {
            let image = try await imageSource.capture()
            latestImageData = image.data
            statusMessage = AppMessage(.statusDescribingScene)

            let description = try await sceneDescriber.describe(
                image,
                language: language
            )
            latestDescription = description
            statusMessage = AppMessage(.statusDescriptionReady)
            try speechOutput.speak(
                description.text,
                language: description.language
            )
        } catch {
            report(error, language: language, speak: true)
        }
    }

    @discardableResult
    func capturePlaceView(
        label: String,
        into existingPlace: Place?,
        modelContext: ModelContext,
        language: SupportedLanguage
    ) async -> Place? {
        guard !isBusy else {
            return existingPlace
        }

        let normalizedLabel = label.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedLabel.isEmpty else {
            report(
                PlaceWorkflowError.missingLabel,
                language: language,
                speak: true
            )
            return existingPlace
        }

        isEnrolling = true
        statusMessage = AppMessage(
            .statusCapturingPlaceView,
            argument: existingPlace?.label ?? normalizedLabel
        )
        errorMessage = nil
        defer { isEnrolling = false }

        var savedImage: StoredImage?
        do {
            let image = try await imageSource.capture()
            let saved = try await imageStore.save(image)
            savedImage = saved
            let embedding = try await imageEmbedder.embed(image)

            let place = existingPlace ?? Place(label: normalizedLabel)
            if existingPlace == nil {
                modelContext.insert(place)
            }
            let snapshot = PlaceSnapshot(
                imageFilename: saved.filename,
                embedding: embedding,
                capturedAt: image.capturedAt,
                location: locationProvider.latestSnapshot
            )
            place.snapshots.append(snapshot)
            try modelContext.save()

            latestImageData = image.data
            storedImages.insert(saved, at: 0)
            statusMessage = AppMessage(
                .statusSavedPlaceView,
                arguments: [
                    String(place.snapshots.count),
                    place.label
                ]
            )

            do {
                try speechOutput.speak(
                    statusMessage.localized(in: language),
                    language: language
                )
            } catch {
                report(error, language: language)
            }
            return place
        } catch {
            modelContext.rollback()
            if let savedImage {
                do {
                    try await imageStore.delete(
                        filename: savedImage.filename
                    )
                } catch {
                    report(
                        PlaceWorkflowError.saveFailed,
                        language: language,
                        speak: true
                    )
                    return existingPlace
                }
            }
            let reportedError = error as? any AppMessageProviding
                ?? PlaceWorkflowError.saveFailed
            report(
                reportedError,
                language: language,
                speak: true
            )
            return existingPlace
        }
    }

    func recognizePlace(
        in places: [Place],
        modelContext: ModelContext,
        language: SupportedLanguage
    ) async {
        guard !isBusy else {
            return
        }
        guard !places.isEmpty else {
            report(
                PlaceWorkflowError.noRememberedPlaces,
                language: language,
                speak: true
            )
            return
        }

        isRecognizing = true
        statusMessage = AppMessage(.statusCheckingLocation)
        errorMessage = nil
        latestPlaceResult = nil
        defer { isRecognizing = false }

        do {
            try await migratePlaceEmbeddingsIfNeeded(
                in: places,
                modelContext: modelContext
            )
            try Task.checkCancellation()
            statusMessage = AppMessage(.statusCheckingLocation)

            let image = try await imageSource.capture()
            try Task.checkCancellation()
            latestImageData = image.data
            let query = try await imageEmbedder.embed(image)
            try Task.checkCancellation()
            let candidates = try placeCandidates(from: places)
            let result = try placeMatcher.match(
                query: query,
                candidates: candidates,
                queryLocation: locationProvider.latestSnapshot
            )

            let message: AppMessage
            switch result {
            case let .matched(match):
                message = AppMessage(
                    .placeMatched,
                    argument: match.label
                )
            case .uncertain:
                message = AppMessage(.placeUncertain)
            }
            let output = PlaceRecognitionOutput(
                message: message,
                language: language
            )
            latestPlaceResult = output
            statusMessage = AppMessage(.statusPlaceRecognitionComplete)
            try Task.checkCancellation()
            try speechOutput.speak(
                output.text,
                language: language
            )
        } catch is CancellationError {
            statusMessage = AppMessage(.statusReady)
            errorMessage = nil
        } catch {
            report(error, language: language, speak: true)
        }
    }

    func stopNavigationOutput() {
        speechOutput.stop()
    }

    func rename(
        _ place: Place,
        to label: String,
        modelContext: ModelContext
    ) throws {
        let normalized = label.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            throw PlaceWorkflowError.missingLabel
        }
        place.label = normalized
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw PlaceWorkflowError.updateFailed
        }
    }

    func delete(
        _ place: Place,
        modelContext: ModelContext
    ) async throws {
        let filenames = place.snapshots.map(\.imageFilename)
        var deletedFilenames = Set<String>()
        do {
            for filename in filenames {
                try await imageStore.delete(filename: filename)
                deletedFilenames.insert(filename)
            }
        } catch {
            storedImages.removeAll {
                deletedFilenames.contains($0.filename)
            }
            throw PlaceWorkflowError.deleteFailed
        }

        modelContext.delete(place)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw PlaceWorkflowError.deleteFailed
        }

        storedImages.removeAll {
            filenames.contains($0.filename)
        }
    }

    func statusText(language: SupportedLanguage) -> String {
        statusMessage.localized(in: language)
    }

    func errorText(language: SupportedLanguage) -> String? {
        errorMessage?.localized(in: language)
    }

    private var isBusy: Bool {
        isCapturing || isDescribing || isRecognizing || isEnrolling
    }

    private func placeCandidates(
        from places: [Place]
    ) throws -> [PlaceCandidate] {
        var candidates: [PlaceCandidate] = []
        var invalidSnapshotCount = 0
        var validSnapshotCount = 0

        for place in places {
            var snapshots: [PlaceCandidate.Snapshot] = []
            for snapshot in place.snapshots {
                do {
                    snapshots.append(
                        PlaceCandidate.Snapshot(
                            embedding: try snapshot.imageEmbedding(),
                            location: snapshot.locationSnapshot
                        )
                    )
                    validSnapshotCount += 1
                } catch is ImageEmbeddingError {
                    invalidSnapshotCount += 1
                }
            }
            if !snapshots.isEmpty {
                candidates.append(
                    PlaceCandidate(
                        id: place.id,
                        label: place.label,
                        snapshots: snapshots
                    )
                )
            }
        }

        if invalidSnapshotCount > 0 {
            Self.logger.error(
                "Skipped \(invalidSnapshotCount) invalid place snapshots"
            )
        }
        if invalidSnapshotCount > 0, validSnapshotCount == 0 {
            throw ImageEmbeddingError.invalidPayload
        }
        return candidates
    }

    private func migratePlaceEmbeddingsIfNeeded(
        in places: [Place],
        modelContext: ModelContext
    ) async throws {
        let outdatedSnapshots = places
            .flatMap(\.snapshots)
            .filter {
                $0.embeddingModel != imageEmbedder.modelIdentifier
            }
        guard !outdatedSnapshots.isEmpty else {
            return
        }

        statusMessage = AppMessage(.statusUpdatingPlaceEmbeddings)
        var updatedCount = 0
        var failureCount = 0

        for snapshot in outdatedSnapshots {
            try Task.checkCancellation()
            do {
                let data = try await imageStore.load(
                    filename: snapshot.imageFilename
                )
                let image = CapturedImage(
                    data: data,
                    format: .jpeg,
                    capturedAt: snapshot.capturedAt
                )
                let embedding = try await imageEmbedder.embed(image)
                try Task.checkCancellation()
                snapshot.replaceEmbedding(with: embedding)
                updatedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failureCount += 1
            }
        }

        if updatedCount > 0 {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw PlaceWorkflowError.migrationFailed
            }
        }

        if failureCount > 0 {
            Self.logger.error(
                "Failed to update \(failureCount) place embeddings"
            )
        }
        let hasCurrentEmbedding = places
            .flatMap(\.snapshots)
            .contains {
                $0.embeddingModel == imageEmbedder.modelIdentifier
            }
        if !hasCurrentEmbedding {
            throw PlaceWorkflowError.migrationFailed
        }
    }

    private func report(
        _ error: any Error,
        language: SupportedLanguage,
        speak: Bool = false
    ) {
        let message = AppErrorMessage.message(
            for: error,
            language: language
        )
        statusMessage = message
        errorMessage = message
        let localizedMessage = message.localized(in: language)

        if speak {
            do {
                try speechOutput.speak(
                    localizedMessage,
                    language: language
                )
            } catch {
                feedback.announceFailure(
                    localizedMessage,
                    language: language
                )
            }
        } else {
            feedback.announceFailure(
                localizedMessage,
                language: language
            )
        }
    }
}

enum PlaceWorkflowError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case missingLabel
    case saveFailed
    case updateFailed
    case deleteFailed
    case noRememberedPlaces
    case migrationFailed

    var appMessage: AppMessage {
        switch self {
        case .missingLabel:
            AppMessage(.errorPlaceMissingLabel)
        case .saveFailed:
            AppMessage(.errorPlaceSave)
        case .updateFailed:
            AppMessage(.errorPlaceUpdate)
        case .deleteFailed:
            AppMessage(.errorPlaceDelete)
        case .noRememberedPlaces:
            AppMessage(.errorNoRememberedPlaces)
        case .migrationFailed:
            AppMessage(.errorPlaceMigration)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}
