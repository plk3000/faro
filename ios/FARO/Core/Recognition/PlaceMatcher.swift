import CoreLocation
import Foundation

struct PlaceCandidate: Sendable {
    struct Snapshot: Sendable {
        let embedding: ImageEmbedding
        let location: LocationSnapshot?
    }

    let id: UUID
    let label: String
    let snapshots: [Snapshot]
}

struct PlaceMatch: Equatable, Sendable {
    let placeID: UUID
    let label: String
    let distance: Double
    let confidence: Double
}

enum PlaceMatchResult: Equatable, Sendable {
    case matched(PlaceMatch)
    case uncertain
}

struct PlaceMatchingPolicy: Equatable, Sendable {
    let maximumDistance: Double
    let minimumSeparation: Double

    static func defaultPolicy(for modelIdentifier: String) -> Self {
        if modelIdentifier == PixelGridEmbedder.identifier {
            return Self(
                maximumDistance: 3,
                minimumSeparation: 0.35
            )
        }
        return Self(
            maximumDistance: 10,
            minimumSeparation: 0.75
        )
    }
}

struct GPSCandidateFilter: Sendable {
    let siteRadiusMeters: CLLocationDistance
    let maximumAccuracyAllowanceMeters: CLLocationDistance

    init(
        siteRadiusMeters: CLLocationDistance = 500,
        maximumAccuracyAllowanceMeters: CLLocationDistance = 250
    ) {
        self.siteRadiusMeters = siteRadiusMeters
        self.maximumAccuracyAllowanceMeters =
            maximumAccuracyAllowanceMeters
    }

    func candidates(
        from candidates: [PlaceCandidate],
        near queryLocation: LocationSnapshot?
    ) -> [PlaceCandidate] {
        guard let queryLocation else {
            return candidates
        }

        let query = CLLocation(
            latitude: queryLocation.latitude,
            longitude: queryLocation.longitude
        )

        return candidates.filter { candidate in
            let savedLocations = candidate.snapshots.compactMap(\.location)
            guard !savedLocations.isEmpty else {
                return true
            }
            return savedLocations.contains { saved in
                let savedLocation = CLLocation(
                    latitude: saved.latitude,
                    longitude: saved.longitude
                )
                let queryAccuracy = min(
                    maximumAccuracyAllowanceMeters,
                    max(0, queryLocation.horizontalAccuracy)
                )
                let savedAccuracy = min(
                    maximumAccuracyAllowanceMeters,
                    max(0, saved.horizontalAccuracy)
                )
                return query.distance(from: savedLocation)
                    <= siteRadiusMeters + queryAccuracy + savedAccuracy
            }
        }
    }
}

struct PlaceMatcher: Sendable {
    private struct Neighbor {
        let placeID: UUID
        let label: String
        let distance: Double
    }

    let embedder: any ImageEmbedder
    let policy: PlaceMatchingPolicy
    let gpsFilter: GPSCandidateFilter

    init(
        embedder: any ImageEmbedder,
        policy: PlaceMatchingPolicy? = nil,
        gpsFilter: GPSCandidateFilter = GPSCandidateFilter()
    ) {
        self.embedder = embedder
        self.policy = policy
            ?? .defaultPolicy(for: embedder.modelIdentifier)
        self.gpsFilter = gpsFilter
    }

    func match(
        query: ImageEmbedding,
        candidates: [PlaceCandidate],
        queryLocation: LocationSnapshot?
    ) throws -> PlaceMatchResult {
        let filtered = gpsFilter.candidates(
            from: candidates,
            near: queryLocation
        )

        var neighbors: [Neighbor] = []
        for candidate in filtered {
            for snapshot in candidate.snapshots
                where snapshot.embedding.modelIdentifier
                    == query.modelIdentifier {
                let distance = try embedder.distance(
                    between: query,
                    and: snapshot.embedding
                )
                if distance <= policy.maximumDistance {
                    neighbors.append(
                        Neighbor(
                            placeID: candidate.id,
                            label: candidate.label,
                            distance: distance
                        )
                    )
                }
            }
        }

        guard let winner = neighbors.min(
            by: { $0.distance < $1.distance }
        ) else {
            return .uncertain
        }

        let competingDistance = neighbors
            .filter { $0.placeID != winner.placeID }
            .map(\.distance)
            .min()
        if let competingDistance,
           competingDistance - winner.distance
                < policy.minimumSeparation {
            return .uncertain
        }

        let confidence = max(
            0,
            min(1, 1 - winner.distance / policy.maximumDistance)
        )
        return .matched(
            PlaceMatch(
                placeID: winner.placeID,
                label: winner.label,
                distance: winner.distance,
                confidence: confidence
            )
        )
    }
}
