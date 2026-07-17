import Foundation
import CoreLocation

// MARK: - Location Result

struct LocationResult {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let name: String
    let source: String
}

// MARK: - Location Service

/// Shared location provider used by GetLocationTool and WeatherTool.
/// Eliminates the ~120 lines of duplicated GPS/IP code.
actor LocationService {
    static let shared = LocationService()

    /// TTL for cached location in seconds.
    private let cacheTTL: TimeInterval = 120
    private var cachedResult: (result: LocationResult, timestamp: Date)?

    // MARK: - Public API

    /// Best-effort location: GPS first, IP fallback. Results cached for 2 min.
    func best(timeout: TimeInterval = 8) async throws -> LocationResult {
        if let cached = cachedResult, Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.result
        }
        if let gps = try? await gps(timeout: timeout) {
            cachedResult = (gps, Date())
            return gps
        }
        let ip = try await ip()
        cachedResult = (ip, Date())
        return ip
    }

    /// GPS-only location via CLLocationUpdate.liveUpdates(). Returns nil if permission denied or timeout.
    func gps(timeout: TimeInterval = 8) async throws -> LocationResult {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            throw LocationServiceError.permissionDenied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            let start = Date()
            while manager.authorizationStatus == .notDetermined {
                if Date().timeIntervalSince(start) > 10 {
                    throw LocationServiceError.permissionDenied
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard manager.authorizationStatus == .authorizedWhenInUse
                    || manager.authorizationStatus == .authorizedAlways else {
                throw LocationServiceError.permissionDenied
            }
        default: break
        }

        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask {
                let updates = CLLocationUpdate.liveUpdates()
                for try await update in updates {
                    guard let loc = update.location, loc.horizontalAccuracy >= 0 else { continue }
                    return loc
                }
                throw LocationServiceError.unavailable
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw LocationServiceError.timeout
            }
            let loc = try await group.next()!
            group.cancelAll()

            let name = try? await reverseGeocode(loc)
            return LocationResult(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                altitude: loc.altitude,
                horizontalAccuracy: loc.horizontalAccuracy,
                name: name ?? "\(loc.coordinate.latitude), \(loc.coordinate.longitude)",
                source: "gps"
            )
        }
    }

    /// IP-based fallback via ipapi.co. Used when GPS is unavailable.
    func ip() async throws -> LocationResult {
        guard let url = URL(string: "https://ipapi.co/json/") else {
            throw LocationServiceError.unavailable
        }
        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocationServiceError.unavailable
        }
        let city = json["city"] as? String ?? ""
        let region = json["region"] as? String ?? ""
        let country = json["country_name"] as? String ?? ""
        let name = [city, region, country].filter { !$0.isEmpty }.joined(separator: ", ")
        return LocationResult(
            latitude: json["latitude"] as? Double ?? 0,
            longitude: json["longitude"] as? Double ?? 0,
            altitude: 0,
            horizontalAccuracy: 5000,
            name: name.isEmpty ? "unknown" : name,
            source: "ip"
        )
    }

    // MARK: - Private

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let place = placemarks.first else {
            return "\(location.coordinate.latitude), \(location.coordinate.longitude)"
        }
        return [place.locality, place.administrativeArea, place.country]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Errors

enum LocationServiceError: LocalizedError {
    case permissionDenied
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied. Enable in Settings > Privacy > Location Services."
        case .unavailable:
            return "Could not determine location. Try again."
        case .timeout:
            return "Location request timed out. Try again with a clearer sky view."
        }
    }
}
