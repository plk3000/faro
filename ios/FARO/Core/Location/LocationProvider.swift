import CoreLocation
import Observation

struct LocationSnapshot: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let headingDegrees: Double?
}

struct LocationFixPolicy: Equatable, Sendable {
    let maximumAge: TimeInterval
    let maximumHorizontalAccuracy: CLLocationAccuracy

    static let placeMemory = LocationFixPolicy(
        maximumAge: 60,
        maximumHorizontalAccuracy: 250
    )

    func accepts(
        _ location: CLLocation,
        now: Date = .now
    ) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return age >= -5
            && age <= maximumAge
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
    }
}

@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var latestSnapshot: LocationSnapshot? { get }

    func requestAuthorization() async
    func start()
    func stop()
}

@MainActor
@Observable
final class LocationProvider:
    NSObject,
    LocationProviding,
    @preconcurrency CLLocationManagerDelegate
{
    private let manager: CLLocationManager
    private let fixPolicy: LocationFixPolicy
    private var authorizationWaiters:
        [UUID: CheckedContinuation<Void, Never>] = [:]

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var latestSnapshot: LocationSnapshot?

    init(
        manager: CLLocationManager = CLLocationManager(),
        fixPolicy: LocationFixPolicy = .placeMemory
    ) {
        self.manager = manager
        self.fixPolicy = fixPolicy
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 10
        manager.headingFilter = 10
    }

    func requestAuthorization() async {
        authorizationStatus = manager.authorizationStatus
        guard authorizationStatus == .notDetermined else {
            return
        }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                authorizationWaiters[waiterID] = continuation
                authorizationStatus = manager.authorizationStatus
                if authorizationStatus == .notDetermined {
                    manager.requestWhenInUseAuthorization()
                } else {
                    resumeAuthorizationWaiter(waiterID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeAuthorizationWaiter(waiterID)
            }
        }
    }

    func start() {
        guard authorizationStatus == .authorizedWhenInUse
                || authorizationStatus == .authorizedAlways else {
            return
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus != .notDetermined {
            let waiters = Array(authorizationWaiters.values)
            authorizationWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
        if authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways {
            start()
        } else {
            stop()
        }
    }

    private func resumeAuthorizationWaiter(_ id: UUID) {
        authorizationWaiters.removeValue(forKey: id)?.resume()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last,
              fixPolicy.accepts(location) else {
            return
        }
        latestSnapshot = LocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            headingDegrees: latestSnapshot?.headingDegrees
        )
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        guard let current = latestSnapshot,
              newHeading.headingAccuracy >= 0 else {
            return
        }
        latestSnapshot = LocationSnapshot(
            latitude: current.latitude,
            longitude: current.longitude,
            horizontalAccuracy: current.horizontalAccuracy,
            headingDegrees: newHeading.trueHeading >= 0
                ? newHeading.trueHeading
                : newHeading.magneticHeading
        )
    }
}
