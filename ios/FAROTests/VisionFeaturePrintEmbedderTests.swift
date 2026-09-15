import Foundation
import Testing
@testable import FARO

struct VisionFeaturePrintEmbedderTests {
    @Test
    func usesVersionedCodableObservationIdentifier() {
        #expect(
            VisionFeaturePrintEmbedder.identifier
                == "apple-vision-feature-print-revision-2-codable-v1"
        )
    }

    @Test
    func rejectsRawVectorsTaggedAsCodableObservations() {
        let embedder = VisionFeaturePrintEmbedder()
        let rawVector = ImageEmbedding(
            modelIdentifier: embedder.modelIdentifier,
            payload: Data(repeating: 0, count: 4),
            componentType: .float32,
            componentCount: 1
        )

        #expect(throws: ImageEmbeddingError.invalidPayload) {
            _ = try embedder.distance(
                between: rawVector,
                and: rawVector
            )
        }
    }

#if !targetEnvironment(simulator)
    @Test
    func similarViewsAreCloserThanDifferentRooms() async throws {
        let source = FixtureImageSource(
            resourceNames: ["kitchen-a", "kitchen-b", "bedroom-a"]
        )
        let embedder = VisionFeaturePrintEmbedder()

        let kitchenA = try await embedder.embed(source.capture())
        let kitchenB = try await embedder.embed(source.capture())
        let bedroom = try await embedder.embed(source.capture())

        let sameRoomDistance = try embedder.distance(
            between: kitchenA,
            and: kitchenB
        )
        let differentRoomDistance = try embedder.distance(
            between: kitchenA,
            and: bedroom
        )

        #expect(sameRoomDistance < differentRoomDistance)
    }
#endif

    @Test
    func rejectsEmbeddingsFromAnotherModel() throws {
        let embedder = VisionFeaturePrintEmbedder()
        let featurePrint = ImageEmbedding(
            modelIdentifier: embedder.modelIdentifier,
            payload: Data(repeating: 0, count: 4),
            componentType: .float32,
            componentCount: 1
        )
        let incompatible = ImageEmbedding(
            modelIdentifier: "other-model",
            payload: featurePrint.payload,
            componentType: featurePrint.componentType,
            componentCount: featurePrint.componentCount
        )

        do {
            _ = try embedder.distance(
                between: featurePrint,
                and: incompatible
            )
            Issue.record("Expected incompatibleModels")
        } catch {
            #expect(error as? ImageEmbeddingError == .incompatibleModels)
        }
    }
}

struct PixelGridEmbedderTests {
    @Test
    func similarViewsAreCloserThanDifferentRooms() async throws {
        let source = FixtureImageSource(
            resourceNames: ["kitchen-a", "kitchen-b", "bedroom-a"]
        )
        let embedder = PixelGridEmbedder()

        let kitchenA = try await embedder.embed(source.capture())
        let kitchenB = try await embedder.embed(source.capture())
        let bedroom = try await embedder.embed(source.capture())

        let sameRoomDistance = try embedder.distance(
            between: kitchenA,
            and: kitchenB
        )
        let differentRoomDistance = try embedder.distance(
            between: kitchenA,
            and: bedroom
        )

        #expect(sameRoomDistance < differentRoomDistance)
    }
}
