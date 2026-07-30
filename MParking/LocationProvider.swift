import CoreLocation
import Observation
import ParkingKit

/// Coarse location, only while the app is in use, only to sort by distance.
@Observable
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var latitude: Double?
    private(set) var longitude: Double?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    /// Roughly the middle of Central Campus.
    static let campusCentre = (lat: 42.2780, lon: -83.7382)
    /// Beyond this, distances to Ann Arbor lots are true but useless - showing
    /// "2050.4 mi" as a decision aid is noise, so the app drops distance entirely
    /// and falls back to sorting by name.
    static let inAreaRadiusMetres: Double = 40_000

    var coordinate: (lat: Double, lon: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }

    /// Nil when the user is outside the Ann Arbor area.
    var localCoordinate: (lat: Double, lon: Double)? {
        guard let coordinate, isNearAnnArbor else { return nil }
        return coordinate
    }

    var isNearAnnArbor: Bool {
        guard let coordinate else { return false }
        return ParkingRules.metres(from: coordinate, to: Self.campusCentre)
            <= Self.inAreaRadiusMetres
    }

    /// True only when we have a fix and it is far from campus.
    var isOutOfArea: Bool {
        coordinate != nil && !isNearAnnArbor
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    override init() {
        super.init()
        manager.delegate = self
        // Sorting a list by distance does not need better than ~100m.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        authorization = manager.authorizationStatus
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the status here, then hop to the main actor and use our own
        // manager reference - forwarding the callback's instance across the
        // isolation boundary would be a data race.
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let lat = last.coordinate.latitude
        let lon = last.coordinate.longitude
        Task { @MainActor in
            self.latitude = lat
            self.longitude = lon
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Distance is a nicety; a failure just means the list stays alphabetical.
    }
}
