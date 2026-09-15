import Foundation
import SwiftData
import Testing
@testable import FARO

@MainActor
struct PlacePersistenceTests {
    @Test
    func placeAndSnapshotsPersist() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Place.self,
            PlaceSnapshot.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let place = Place(label: "Kitchen")
        let embedding = ImageEmbedding(
            modelIdentifier: PixelGridEmbedder.identifier,
            payload: Data(repeating: 0, count: 4),
            componentType: .float32,
            componentCount: 1
        )
        let snapshot = PlaceSnapshot(
            imageFilename: "fixture.png",
            embedding: embedding,
            location: LocationSnapshot(
                latitude: 47.6,
                longitude: -122.3,
                horizontalAccuracy: 25,
                headingDegrees: 90
            )
        )
        place.snapshots.append(snapshot)
        context.insert(place)
        try context.save()

        let reloadedContext = ModelContext(container)
        let places = try reloadedContext.fetch(FetchDescriptor<Place>())

        #expect(places.count == 1)
        #expect(places.first?.label == "Kitchen")
        #expect(places.first?.snapshots.count == 1)
        #expect(places.first?.snapshots.first?.latitude == 47.6)
        #expect(
            try places.first?.snapshots.first?.imageEmbedding()
                == embedding
        )
    }
}
