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

struct PlaceMatchEvaluation: Equatable, Sendable {
    let result: PlaceMatchResult
    let nearestPlaceID: UUID?
    let nearestLabel: String?
    let nearestDistance: Double?
    let nearestCompetingDistance: Double?
    let candidateCount: Int
    let snapshotCount: Int
    let policy: PlaceMatchingPolicy
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
        if modelIdentifier == VisionFeaturePrintEmbedder.identifier {
            return Self(
                maximumDistance: 0.5,
                minimumSeparation: 0.05
            )
        }
        return Self(
            maximumDistance: 0.5,
            minimumSeparation: 0.05
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
        try evaluate(
            query: query,
            candidates: candidates,
            queryLocation: queryLocation
        ).result
    }

    func evaluate(
        query: ImageEmbedding,
        candidates: [PlaceCandidate],
        queryLocation: LocationSnapshot?
    ) throws -> PlaceMatchEvaluation {
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
                neighbors.append(
                    Neighbor(
                        placeID: candidate.id,
                        label: candidate.label,
                        distance: distance
                    )
                )
            }
        }

        guard let winner = neighbors.min(
            by: { $0.distance < $1.distance }
        ) else {
            return PlaceMatchEvaluation(
                result: .uncertain,
                nearestPlaceID: nil,
                nearestLabel: nil,
                nearestDistance: nil,
                nearestCompetingDistance: nil,
                candidateCount: filtered.count,
                snapshotCount: 0,
                policy: policy
            )
        }

        let competingDistance = neighbors
            .filter { $0.placeID != winner.placeID }
            .map(\.distance)
            .min()
        let decisionCompetingDistance = neighbors
            .filter {
                $0.placeID != winner.placeID
                    && $0.distance <= policy.maximumDistance
            }
            .map(\.distance)
            .min()
        let isWithinMaximumDistance =
            winner.distance <= policy.maximumDistance
        let hasRequiredSeparation =
            decisionCompetingDistance.map {
                $0 - winner.distance >= policy.minimumSeparation
            } ?? true

        let result: PlaceMatchResult
        if isWithinMaximumDistance && hasRequiredSeparation {
            let confidence = max(
                0,
                min(1, 1 - winner.distance / policy.maximumDistance)
            )
            result = .matched(
                PlaceMatch(
                    placeID: winner.placeID,
                    label: winner.label,
                    distance: winner.distance,
                    confidence: confidence
                )
            )
        } else {
            result = .uncertain
        }

        return PlaceMatchEvaluation(
            result: result,
            nearestPlaceID: winner.placeID,
            nearestLabel: winner.label,
            nearestDistance: winner.distance,
            nearestCompetingDistance: competingDistance,
            candidateCount: filtered.count,
            snapshotCount: neighbors.count,
            policy: policy
        )
    }
}
