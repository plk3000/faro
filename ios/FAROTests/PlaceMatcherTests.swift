import Foundation
import Testing
@testable import FARO

struct PlaceMatcherTests {
    private let embedder = PixelGridEmbedder()
    private let kitchenID = UUID()
    private let bedroomID = UUID()

    @Test
    func returnsConfidentNearestNeighborVote() throws {
        let matcher = PlaceMatcher(
            embedder: embedder,
            policy: PlaceMatchingPolicy(
                maximumDistance: 1,
                minimumSeparation: 0.2,
                neighborCount: 3
            )
        )
        let candidates = [
            candidate(
                id: kitchenID,
                label: "Kitchen",
                values: [0, 0.1, 0.2]
            ),
            candidate(
                id: bedroomID,
                label: "Bedroom",
                values: [2, 2.1]
            )
        ]

        let result = try matcher.match(
            query: embedding(0.05),
            candidates: candidates,
            queryLocation: nil
        )

        guard case let .matched(match) = result else {
            Issue.record("Expected a match")
            return
        }
        #expect(match.placeID == kitchenID)
        #expect(match.label == "Kitchen")
    }

    @Test
    func reportsUncertainBelowThreshold() throws {
        let matcher = PlaceMatcher(
            embedder: embedder,
            policy: PlaceMatchingPolicy(
                maximumDistance: 0.25,
                minimumSeparation: 0.1,
                neighborCount: 3
            )
        )

        let result = try matcher.match(
            query: embedding(1),
            candidates: [
                candidate(
                    id: kitchenID,
                    label: "Kitchen",
                    values: [0]
                )
            ],
            queryLocation: nil
        )

        #expect(result == .uncertain)
    }

    @Test
    func reportsUncertainForTiedPlaces() throws {
        let matcher = PlaceMatcher(
            embedder: embedder,
            policy: PlaceMatchingPolicy(
                maximumDistance: 2,
                minimumSeparation: 0.2,
                neighborCount: 2
            )
        )

        let result = try matcher.match(
            query: embedding(0.5),
            candidates: [
                candidate(
                    id: kitchenID,
                    label: "Kitchen",
                    values: [0]
                ),
                candidate(
                    id: bedroomID,
                    label: "Bedroom",
                    values: [1]
                )
            ],
            queryLocation: nil
        )

        #expect(result == .uncertain)
    }

    @Test
    func gpsFiltersCandidatesBySiteNotRoom() throws {
        let matcher = PlaceMatcher(
            embedder: embedder,
            policy: PlaceMatchingPolicy(
                maximumDistance: 2,
                minimumSeparation: 0.2,
                neighborCount: 3
            ),
            gpsFilter: GPSCandidateFilter(siteRadiusMeters: 500)
        )
        let nearby = LocationSnapshot(
            latitude: 47.6062,
            longitude: -122.3321,
            horizontalAccuracy: 30,
            headingDegrees: nil
        )
        let farAway = LocationSnapshot(
            latitude: 40.7128,
            longitude: -74.0060,
            horizontalAccuracy: 30,
            headingDegrees: nil
        )

        let result = try matcher.match(
            query: embedding(0),
            candidates: [
                candidate(
                    id: kitchenID,
                    label: "Kitchen",
                    values: [0.1],
                    location: nearby
                ),
                candidate(
                    id: bedroomID,
                    label: "Remote office",
                    values: [0],
                    location: farAway
                )
            ],
            queryLocation: nearby
        )

        guard case let .matched(match) = result else {
            Issue.record("Expected a nearby-site match")
            return
        }
        #expect(match.placeID == kitchenID)
    }

    @Test
    func gpsAccuracyIsBoundedSoPoorFixesDoNotMergeSites() throws {
        let matcher = PlaceMatcher(
            embedder: embedder,
            policy: PlaceMatchingPolicy(
                maximumDistance: 2,
                minimumSeparation: 0.2,
                neighborCount: 3
            ),
            gpsFilter: GPSCandidateFilter(
                siteRadiusMeters: 500,
                maximumAccuracyAllowanceMeters: 250
            )
        )
        let queryLocation = LocationSnapshot(
            latitude: 47.6062,
            longitude: -122.3321,
            horizontalAccuracy: 10_000,
            headingDegrees: nil
        )
        let otherSite = LocationSnapshot(
            latitude: 47.6162,
            longitude: -122.3321,
            horizontalAccuracy: 10_000,
            headingDegrees: nil
        )

        let result = try matcher.match(
            query: embedding(0),
            candidates: [
                candidate(
                    id: bedroomID,
                    label: "Other site",
                    values: [0],
                    location: otherSite
                )
            ],
            queryLocation: queryLocation
        )

        #expect(result == .uncertain)
    }

    private func candidate(
        id: UUID,
        label: String,
        values: [Float],
        location: LocationSnapshot? = nil
    ) -> PlaceCandidate {
        PlaceCandidate(
            id: id,
            label: label,
            snapshots: values.map {
                PlaceCandidate.Snapshot(
                    embedding: embedding($0),
                    location: location
                )
            }
        )
    }

    private func embedding(_ value: Float) -> ImageEmbedding {
        var bits = value.bitPattern.littleEndian
        let data = Swift.withUnsafeBytes(of: &bits) { Data($0) }
        return ImageEmbedding(
            modelIdentifier: embedder.modelIdentifier,
            payload: data,
            componentType: .float32,
            componentCount: 1
        )
    }
}
