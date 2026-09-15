import CoreLocation
import Foundation
import Testing
@testable import FARO

struct LocationProviderTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let policy = LocationFixPolicy(
        maximumAge: 60,
        maximumHorizontalAccuracy: 250
    )

    @Test
    func acceptsFreshAccurateFix() {
        let location = makeLocation(
            age: 10,
            horizontalAccuracy: 40
        )

        #expect(policy.accepts(location, now: now))
    }

    @Test
    func rejectsCachedOrImpreciseFixes() {
        #expect(
            !policy.accepts(
                makeLocation(age: 120, horizontalAccuracy: 40),
                now: now
            )
        )
        #expect(
            !policy.accepts(
                makeLocation(age: 10, horizontalAccuracy: 500),
                now: now
            )
        )
    }

    private func makeLocation(
        age: TimeInterval,
        horizontalAccuracy: CLLocationAccuracy
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 47.6062,
                longitude: -122.3321
            ),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 20,
            timestamp: now.addingTimeInterval(-age)
        )
    }
}
