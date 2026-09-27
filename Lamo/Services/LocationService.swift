import Foundation
import CoreLocation
import MapKit

// MARK: - Location Result

nonisolated struct LocationResult: Sendable {
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

    /// Retained across calls: a locally-created CLLocationManager is released
    /// at the end of `gps()`, which can cancel the auth prompt / live updates.
    private var locationManager: CLLocationManager?
    /// Reverse-geocode cache (rounded lat/lon → name, timestamp).
    private var geocodeCache: [String: (name: String, timestamp: Date)] = [:]

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
        try Task.checkCancellation()
        let ip = try await ip()
        cachedResult = (ip, Date())
        return ip
    }

    /// GPS-only location via CLLocationUpdate.liveUpdates(). Returns nil if permission denied or timeout.
    func gps(timeout: TimeInterval = 8) async throws -> LocationResult {
        let manager: CLLocationManager
        if let existing = locationManager {
            manager = existing
        } else {
            let created = CLLocationManager()
            locationManager = created
            manager = created
        }
        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            throw LocationServiceError.permissionDenied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            let start = Date()
            while manager.authorizationStatus == .notDetermined {
                try Task.checkCancellation()
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
                    try Task.checkCancellation()
                    guard let loc = update.location,
                          loc.horizontalAccuracy >= 0,
                          loc.horizontalAccuracy < 500 else { continue }
                    return loc
                }
                throw LocationServiceError.unavailable
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw LocationServiceError.timeout
            }
            guard let loc = try await group.next() else {
                group.cancelAll()
                throw LocationServiceError.unavailable
            }
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

    /// IP-based fallback. Primary: ipapi.co; fallback: ipwho.is (no key, generous limits).
    /// Used when GPS is unavailable. Races both providers, first success wins.
    func ip() async throws -> LocationResult {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: LocationResult.self) { group in
            group.addTask { try await self.ipViaIpapi() }
            group.addTask { try await self.ipViaIpwhois() }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw LocationServiceError.unavailable
            }
            group.cancelAll()
            return first
        }
    }

    private struct IpApiResponse: Decodable {
        let latitude: Double
        let longitude: Double
        let city: String?
        let region: String?
        let country: String?

        enum CodingKeys: String, CodingKey {
            case latitude, longitude, city, region
            case country = "country_name"
        }
    }

    private struct IpWhoisResponse: Decodable {
        let success: Bool
        let latitude: Double
        let longitude: Double
        let city: String?
        let region: String?
        let country: String?
    }

    private func ipViaIpapi() async throws -> LocationResult {
        guard let url = URL(string: "https://ipapi.co/json/") else {
            throw LocationServiceError.unavailable
        }
        let response: IpApiResponse = try await fetchJSON(from: url)
        return try makeIPResult(
            latitude: response.latitude,
            longitude: response.longitude,
            city: response.city,
            region: response.region,
            country: response.country
        )
    }

    private func ipViaIpwhois() async throws -> LocationResult {
        guard let url = URL(string: "https://ipwho.is/") else {
            throw LocationServiceError.unavailable
        }
        let response: IpWhoisResponse = try await fetchJSON(from: url)
        guard response.success else { throw LocationServiceError.unavailable }
        return try makeIPResult(
            latitude: response.latitude,
            longitude: response.longitude,
            city: response.city,
            region: response.region,
            country: response.country
        )
    }

    private func fetchJSON<T: Decodable>(from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw LocationServiceError.unavailable
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func makeIPResult(
        latitude: Double,
        longitude: Double,
        city: String?,
        region: String?,
        country: String?
    ) throws -> LocationResult {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw LocationServiceError.unavailable
        }
        let name = [city, region, country]
            .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return LocationResult(
            latitude: latitude,
            longitude: longitude,
            altitude: 0,
            horizontalAccuracy: 5000,
            name: name.isEmpty ? "unknown" : name,
            source: "ip"
        )
    }

    // MARK: - Private
    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        let key = String(format: "%.3f,%.3f", location.coordinate.latitude, location.coordinate.longitude)
        if let cached = geocodeCache[key], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.name
        }
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return "\(location.coordinate.latitude), \(location.coordinate.longitude)"
        }
        let mapItems = try await request.mapItems
        guard let addr = mapItems.first?.addressRepresentations else {
            return "\(location.coordinate.latitude), \(location.coordinate.longitude)"
        }
        let parts = [addr.cityName, addr.regionName].compactMap { $0 }
        let name = parts.isEmpty
            ? "\(location.coordinate.latitude), \(location.coordinate.longitude)"
            : parts.joined(separator: ", ")
        geocodeCache[key] = (name, Date())
        return name
    }
}

// MARK: - Errors

nonisolated enum LocationServiceError: LocalizedError, Sendable {
    case permissionDenied
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "Location permission denied. Enable in Settings > Privacy > Location Services.")
        case .unavailable:
            return String(localized: "Could not determine location. Try again.")
        case .timeout:
            return String(localized: "Location request timed out. Try again with a clearer sky view.")
        }
    }
}
