import Foundation
import LiteRTLM
import UIKit
import EventKit
import CoreLocation

// MARK: - Get Current Time

struct GetCurrentTimeTool: Tool {
    static let name = "get_current_time"
    static let description = "Get the current date, time, day of week, timezone, and Unix timestamp. Use when you need to know what time it is now."

    func run() async throws -> Any {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: now)

        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: now)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US")
        weekdayFormatter.dateFormat = "EEEE"
        let weekday = weekdayFormatter.string(from: now)

        let tz = TimeZone.current
        let tzName = tz.identifier
        let tzOffset = tz.secondsFromGMT() / 3600

        return [
            "iso_date": dateStr,
            "time": timeStr,
            "weekday": weekday,
            "timezone": tzName,
            "utc_offset_hours": tzOffset,
            "unix_timestamp": Int(now.timeIntervalSince1970),
        ] as [String: Any]
    }
}

// MARK: - Calculator

struct CalculatorTool: Tool {
    static let name = "calculator"
    static let description = """
        Evaluate a mathematical expression. Supports +, -, *, /, %, ** (power), sqrt, sin, cos, tan, log, log2, ln, abs, ceil, floor, round, pi, e. \
        Example expressions: "2 + 3 * 4", "sqrt(144)", "sin(pi / 2)", "log(1000)". \
        Returns the numeric result. Use for any calculation to ensure accuracy.
        """

    @ToolParam(description: "The mathematical expression to evaluate.")
    var expression: String

    func run() async throws -> Any {
        let cleaned = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else {
            return ["error": "Empty expression"]
        }

        do {
            let result = try evaluateMath(cleaned)
            return [
                "expression": expression,
                "result": result,
            ] as [String: Any]
        } catch {
            return [
                "expression": expression,
                "error": "\(error)",
            ] as [String: Any]
        }
    }

    private func evaluateMath(_ expr: String) throws -> Double {
        var prepared = expr
        // Replace constants
        prepared = prepared.replacingOccurrences(of: "pi", with: "\(Double.pi)")
        prepared = prepared.replacingOccurrences(of: "e", with: "\(M_E)")

        // Replace ** (power) with calls to pow()
        while let range = prepared.range(of: #"(\d+\.?\d*)\s*\*\*\s*(\d+\.?\d*)"#, options: .regularExpression) {
            let match = String(prepared[range])
            let parts = match.components(separatedBy: "**")
            guard parts.count == 2,
                  let base = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let exp = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
                throw CalcError.invalidExpression
            }
            let result = pow(base, exp)
            prepared.replaceSubrange(range, with: "\(result)")
        }

        // Replace function calls with computed values
        let functions: [(String, (Double) -> Double)] = [
            ("sqrt", { sqrt(max(0, $0)) }),
            ("sin", { sin($0) }),
            ("cos", { cos($0) }),
            ("tan", { tan($0) }),
            ("log", { log10(max(0.000001, $0)) }),
            ("log2", { log2(max(0.000001, $0)) }),
            ("ln", { log(max(0.000001, $0)) }),
            ("abs", { abs($0) }),
            ("ceil", { ceil($0) }),
            ("floor", { floor($0) }),
            ("round", { round($0) }),
        ]

        for (name, fn) in functions {
            while let range = prepared.range(of: "\(name)\\((.*?)\\)", options: .regularExpression) {
                let match = String(prepared[range])
                guard let argStart = match.firstIndex(of: "(") else { break }
                let argStr = String(match[match.index(after: argStart)..<match.index(before: match.endIndex)])
                guard let arg = Double(argStr.trimmingCharacters(in: .whitespaces)) else { break }
                let result = fn(arg)
                prepared.replaceSubrange(range, with: "\(result)")
            }
        }

        // Final evaluation with NSExpression
        let nsExpr = NSExpression(format: prepared)
        guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw CalcError.invalidExpression
        }
        return result.doubleValue
    }
}

private enum CalcError: LocalizedError {
    case invalidExpression
    var errorDescription: String? { "Invalid mathematical expression" }
}

// MARK: - Open URL

struct OpenURLTool: Tool {
    static let name = "open_url"
    static let description = "Open a URL in the system browser (Safari). Use when the user asks to open a link or website."

    @ToolParam(description: "The URL to open. Must start with http:// or https://.")
    var url: String

    func run() async throws -> Any {
        guard let nsurl = URL(string: url),
              nsurl.scheme == "http" || nsurl.scheme == "https" else {
            return ["error": "Invalid URL. Must start with http:// or https://"]
        }

        let opened = await MainActor.run {
            UIApplication.shared.open(nsurl)
        }
        return [
            "opened": opened,
            "url": url,
        ] as [String: Any]
    }
}

// MARK: - Wikipedia

struct WikipediaTool: Tool {
    static let name = "wikipedia"
    static let description = """
        Search Wikipedia for articles and get summaries. \
        Use to look up facts, definitions, biographies, historical events, and general knowledge. \
        Two modes: "search" returns article titles and snippets; "extract" returns the full summary of a specific article. \
        Language defaults to "en" (English).
        """

    @ToolParam(description: "The search query or article title.")
    var query: String

    @ToolParam(description: #"Either "search" to find matching articles, or "extract" to get a summary of a specific article."#)
    var mode: String = "search"

    @ToolParam(description: "Language code (e.g. 'en', 'ru', 'de', 'fr'). Default 'en'.")
    var language: String = "en"

    func run() async throws -> Any {
        let lang = language.isEmpty ? "en" : language
        let base = "https://\(lang).wikipedia.org"

        if mode == "extract" {
            return try await extractPage(query: query, baseURL: base)
        } else {
            return try await searchArticles(query: query, baseURL: base)
        }
    }

    private func searchArticles(query: String, baseURL: String) async throws -> [String: Any] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "\(baseURL)/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&srlimit=5&srprop=snippet"
        guard let url = URL(string: urlStr) else {
            return ["error": "Failed to build search URL"]
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS; on-device AI)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryResult = json["query"] as? [String: Any],
              let search = queryResult["search"] as? [[String: Any]] else {
            return ["error": "Failed to parse search results"]
        }

        let results: [[String: Any]] = search.map { item in
            let title = item["title"] as? String ?? ""
            var snippet = (item["snippet"] as? String) ?? ""
            // Clean HTML tags from snippet
            snippet = snippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            snippet = HTMLEntityDecoder.decode(snippet)
            return [
                "title": title,
                "snippet": snippet,
                "url": "\(baseURL)/wiki/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)",
            ]
        }

        return [
            "query": query,
            "results": results,
        ] as [String: Any]
    }

    private func extractPage(query: String, baseURL: String) async throws -> [String: Any] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "\(baseURL)/w/api.php?action=query&titles=\(encoded)&prop=extracts&exintro=true&explaintext=true&format=json&redirects=1"
        guard let url = URL(string: urlStr) else {
            return ["error": "Failed to build extract URL"]
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS; on-device AI)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryResult = json["query"] as? [String: Any],
              let pages = queryResult["pages"] as? [String: [String: Any]] else {
            return ["error": "Failed to parse page data"]
        }

        for (_, page) in pages {
            if let extract = page["extract"] as? String {
                let title = page["title"] as? String ?? query
                let pageID = page["pageid"] as? Int ?? 0
                return [
                    "title": title,
                    "page_id": pageID,
                    "extract": extract,
                    "url": "\(baseURL)/wiki/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)",
                ] as [String: Any]
            }
        }

        return ["error": "Page not found. Try a different title or use mode: 'search' first."]
    }
}

// MARK: - Device Info

struct DeviceInfoTool: Tool {
    static let name = "get_device_info"
    static let description = "Get information about this device: model name, OS version, battery level, available storage, memory, and uptime. Use when the user asks about their device."

    func run() async throws -> Any {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let totalSpace = totalDiskSpace()
        let freeSpace = freeDiskSpace()

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        let processInfo = ProcessInfo.processInfo
        let uptime = processInfo.systemUptime

        return [
            "device_name": device.name,
            "device_model": device.model,
            "system_name": device.systemName,
            "system_version": device.systemVersion,
            "battery_level": Int(device.batteryLevel * 100),
            "battery_state": batteryStateString(device.batteryState),
            "total_storage": totalSpace.map { formatter.string(fromByteCount: $0) } ?? "unknown",
            "free_storage": freeSpace.map { formatter.string(fromByteCount: $0) } ?? "unknown",
            "physical_memory_gb": String(format: "%.1f", Double(processInfo.physicalMemory) / 1_073_741_824),
            "processor_count": processInfo.processorCount,
            "uptime_seconds": Int(uptime),
            "is_low_power_mode": processInfo.isLowPowerModeEnabled,
        ] as [String: Any]
    }

    private func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }

    private func totalDiskSpace() -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let size = attrs[.systemSize] as? Int64 else { return nil }
        return size
    }

    private func freeDiskSpace() -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let size = attrs[.systemFreeSize] as? Int64 else { return nil }
        return size
    }
}

// MARK: - Get Location (CoreLocation)

struct GetLocationTool: Tool {
    static let name = "get_location"
    static let description = """
        Get your current GPS location using device sensors. \
        Returns city, coordinates, and address. \
        First use will prompt for location permission. \
        Use when you need to know exactly where the user is for weather, navigation, or local information.
        """

    func run() async throws -> Any {
        let location = try await requestCurrentLocation()
        let name = try await reverseGeocode(location)

        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude_m": location.altitude,
            "horizontal_accuracy_m": location.horizontalAccuracy,
            "location_name": name,
        ] as [String: Any]
    }

    private func requestCurrentLocation() async throws -> CLLocation {
        let manager = CLLocationManager()

        // Check authorization
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Wait briefly for user to respond — timeout after 15s
            let start = Date()
            while manager.authorizationStatus == .notDetermined {
                if Date().timeIntervalSince(start) > 15 { throw LocationError.permissionDenied }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
                throw LocationError.permissionDenied
            }
        case .denied, .restricted:
            throw LocationError.permissionDenied
        default:
            break
        }

        // Use CLLocationUpdate.liveUpdates() (iOS 17+)
        let updates = CLLocationUpdate.liveUpdates()
        for try await update in updates {
            guard let loc = update.location, loc.horizontalAccuracy >= 0 else { continue }
            return loc
        }
        throw LocationError.unavailable
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let place = placemarks.first else { return "\(location.coordinate.latitude), \(location.coordinate.longitude)" }

        let parts = [place.locality, place.administrativeArea, place.country].compactMap { $0 }
        return parts.isEmpty ? "\(location.coordinate.latitude), \(location.coordinate.longitude)" : parts.joined(separator: ", ")
    }
}

private enum LocationError: LocalizedError {
    case permissionDenied
    case unavailable
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Location permission denied. Enable in Settings > Privacy > Location Services."
        case .unavailable: return "Could not determine location. Try again."
        }
    }
}
// MARK: - Weather

struct WeatherTool: Tool {
    static let description = """
        Get current weather conditions. Uses Open-Meteo (free, no API key). \
        If no city is provided, auto-detects your GPS location. \
        Returns temperature, humidity, wind speed, conditions, and sunrise/sunset.
        """

    @ToolParam(description: "City name (e.g. 'London', 'Tokyo', 'Moscow'). Leave empty to auto-detect your location.")
    var city: String = ""

    func run() async throws -> Any {
        let coords: Coords
        if city.isEmpty {
            coords = try await detectLocation()
        } else {
            coords = try await geocode(city: city)
        }
        return try await fetchWeather(lat: coords.lat, lon: coords.lon, cityName: coords.name)
    }

    private struct Coords {
        let lat: Double
        let lon: Double
        let name: String
    }

    private func detectLocation() async throws -> Coords {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            let start = Date()
            while manager.authorizationStatus == .notDetermined {
                if Date().timeIntervalSince(start) > 15 { throw WeatherError.cityNotFound }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
                throw WeatherError.cityNotFound
            }
        case .denied, .restricted:
            throw WeatherError.cityNotFound
        default:
            break
        }

        let updates = CLLocationUpdate.liveUpdates()
        for try await update in updates {
            guard let loc = update.location, loc.horizontalAccuracy >= 0 else { continue }
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(loc)
            let name = placemarks.first?.locality ?? "\(loc.coordinate.latitude), \(loc.coordinate.longitude)"
            return Coords(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, name: name)
        }
        throw WeatherError.cityNotFound
    }
        """

    @ToolParam(description: "City name (e.g. 'London', 'Tokyo', 'Moscow'). Leave empty to auto-detect your location.")
    var city: String = ""

    func run() async throws -> Any {
        let coords: Coords
        if city.isEmpty {
            coords = try await detectLocation()
        } else {
            coords = try await geocode(city: city)
        }
        return try await fetchWeather(lat: coords.lat, lon: coords.lon, cityName: coords.name)
    }

    private func geocode(city: String) async throws -> Coords {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlStr = "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json"
        guard let url = URL(string: urlStr) else {
            throw WeatherError.geocodeFailed
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS; on-device AI)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let lat = first["latitude"] as? Double,
              let lon = first["longitude"] as? Double else {
            throw WeatherError.cityNotFound
        }

        let name = (first["name"] as? String) ?? city
        let country = first["country"] as? String
        let displayName = country.map { "\(name), \($0)" } ?? name
        return Coords(lat: lat, lon: lon, name: displayName)
    }

    private func fetchWeather(lat: Double, lon: Double, cityName: String) async throws -> [String: Any] {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,is_day&daily=sunrise,sunset&timezone=auto&forecast_days=1"
        guard let url = URL(string: urlStr) else {
            throw WeatherError.fetchFailed
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS; on-device AI)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any] else {
            throw WeatherError.fetchFailed
        }

        let temp = current["temperature_2m"] as? Double ?? 0
        let feelsLike = current["apparent_temperature"] as? Double ?? temp
        let humidity = current["relative_humidity_2m"] as? Int ?? 0
        let windSpeed = current["wind_speed_10m"] as? Double ?? 0
        let windDir = current["wind_direction_10m"] as? Int ?? 0
        let weatherCode = current["weather_code"] as? Int ?? 0
        let isDay = (current["is_day"] as? Int ?? 1) == 1

        var sunrise: String? = nil
        var sunset: String? = nil
        if let daily = json["daily"] as? [String: Any] {
            if let sunrises = daily["sunrise"] as? [String], let first = sunrises.first {
                sunrise = first
            }
            if let sunsets = daily["sunset"] as? [String], let first = sunsets.first {
                sunset = first
            }
        }

        return [
            "city": cityName,
            "temperature_c": temp,
            "feels_like_c": feelsLike,
            "humidity_percent": humidity,
            "wind_speed_kmh": windSpeed,
            "wind_direction_deg": windDir,
            "conditions": weatherDescription(code: weatherCode, isDay: isDay),
            "is_day": isDay,
            "sunrise": sunrise as Any,
            "sunset": sunset as Any,
        ] as [String: Any]
    }

    private func weatherDescription(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "Clear sky" : "Clear night"
        case 1, 2, 3: return isDay ? "Partly cloudy" : "Partly cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }
}

private enum WeatherError: LocalizedError {
    case geocodeFailed
    case cityNotFound
    case fetchFailed
    var errorDescription: String? {
        switch self {
        case .geocodeFailed: return "Failed to geocode city name"
        case .cityNotFound: return "City not found. Try a more specific name."
        case .fetchFailed: return "Failed to fetch weather data"
        }
    }
}

// MARK: - Create Reminder

struct CreateReminderTool: Tool {
    static let name = "create_reminder"
    static let description = """
        Create a reminder in the system Reminders app. Use when the user asks to be reminded about something. \
        Requires calendar access permission — will ask on first use.
        """

    @ToolParam(description: "The reminder title — what to remind about.")
    var title: String

    @ToolParam(description: "Optional notes or details for the reminder.")
    var notes: String?

    @ToolParam(description: #"Optional due date in ISO 8601 format (e.g. "2026-07-17T18:00:00"). If not provided, creates a reminder without a due date."#)
    var dueDate: String?

    func run() async throws -> Any {
        let store = EKEventStore()

        // Request access
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }

        guard granted else {
            return ["error": "Reminders access denied. Enable in Settings > Privacy > Reminders."]
        }

        return try await MainActor.run {
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            if let notes = notes, !notes.isEmpty {
                reminder.notes = notes
            }
            if let dueDate = dueDate {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                reminder.dueDateComponents = formatter.date(from: dueDate).map { date in
                    Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                }
                // Retry without fractional seconds
                if reminder.dueDateComponents == nil {
                    let formatter2 = ISO8601DateFormatter()
                    formatter2.formatOptions = [.withInternetDateTime]
                    reminder.dueDateComponents = formatter2.date(from: dueDate).map { date in
                        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    }
                }
            }
            reminder.calendar = store.defaultCalendarForNewReminders()

            do {
                try store.save(reminder, commit: true)
                return [
                    "status": "created",
                    "title": title,
                    "due_date": dueDate as Any,
                    "reminder_id": reminder.calendarItemIdentifier,
                ] as [String: Any]
            } catch {
                return ["error": "Failed to save reminder: \(error.localizedDescription)"]
            }
        }
    }
}
