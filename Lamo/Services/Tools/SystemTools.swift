import Foundation
import LiteRTLM
import UIKit
import EventKit
import CoreLocation

// MARK: - Helpers

private func report(_ name: String, params: String) async {
    await ToolCallReporter.shared.reportCall(name: name, params: params)
}
private func reportResult(_ name: String, _ result: Any) async {
    await ToolCallReporter.shared.reportResult(name: name, result: result)
}

// MARK: - Get Current Time

struct GetCurrentTimeTool: Tool {
    static let name = "get_current_time"
    static let description = "Call when user asks about current time, date, day of week, today's date, or time in another timezone. Returns date, time, weekday, timezone, and Unix timestamp. Supports querying any timezone or future/past dates."

    @ToolParam(description: "IANA timezone name like 'Asia/Tokyo', 'Europe/London', 'America/New_York'. Leave empty for device timezone.")
    var timezone: String?

    @ToolParam(description: "Date in YYYY-MM-DD format (e.g. '2026-12-25'). Leave empty for today.")
    var date: String?

    func run() async throws -> Any {
        await report(Self.name, params: "{\"timezone\": \(timezone.map { "\"\($0)\"" } ?? "null"), \"date\": \(date.map { "\"\($0)\"" } ?? "null")}")

        let tz: TimeZone
        if let tzID = timezone, !tzID.isEmpty, let resolved = TimeZone(identifier: tzID) {
            tz = resolved
        } else {
            tz = TimeZone.current
        }

        let targetDate: Date
        if let dateStr = date, !dateStr.isEmpty {
            let fmtr = DateFormatter()
            fmtr.locale = Locale(identifier: "en_US_POSIX")
            fmtr.dateFormat = "yyyy-MM-dd"
            fmtr.timeZone = tz
            targetDate = fmtr.date(from: dateStr) ?? Date()
        } else {
            targetDate = Date()
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = tz
        let dateStr = formatter.string(from: targetDate)

        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: targetDate)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US")
        weekdayFormatter.dateFormat = "EEEE"
        weekdayFormatter.timeZone = tz
        let weekday = weekdayFormatter.string(from: targetDate)

        let result: [String: Any] = [
            "iso_date": dateStr,
            "time": timeStr,
            "weekday": weekday,
            "timezone": tz.identifier,
            "utc_offset_hours": tz.secondsFromGMT(for: targetDate) / 3600,
            "unix_timestamp": Int(targetDate.timeIntervalSince1970),
        ]
        await reportResult(Self.name, result)
        return result
    }
}

// MARK: - Calculator

struct CalculatorTool: Tool {
    static let name = "calculator"
    static let description = """
        Call when user asks to calculate, compute, evaluate math, or convert numbers. \
        Supports +, -, *, /, %, ** (power), ! (factorial), sqrt, sin, cos, tan, asin, acos, atan, \
        log, log2, ln, abs, ceil, floor, round, pi, e. Percentages: "200 * 15%". \
        Scientific notation: "1e6". Example: "2 + 3 * 4", "sqrt(144)", "5!".
        """

    @ToolParam(description: "The mathematical expression to evaluate.")
    var expression: String

    func run() async throws -> Any {
        await report(Self.name, params: "{\"expression\": \"\(expression)\"}")

        let cleaned = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")
            .trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else {
            let result: [String: Any] = ["error": "Empty expression"]
            await reportResult(Self.name, result)
            return result
        }

        do {
            let value = try evaluateMath(cleaned)
            let result: [String: Any] = ["expression": expression, "result": value]
            await reportResult(Self.name, result)
            return result
        } catch {
            let result: [String: Any] = ["expression": expression, "error": "\(error)"]
            await reportResult(Self.name, result)
            return result
        }
    }

    private func evaluateMath(_ expr: String) throws -> Double {
        var prepared = expr

        // Scientific notation: 1e6, 2.5e-3
        prepared = replaceScientificNotation(prepared)

        // Constants
        prepared = prepared.replacingOccurrences(of: "pi", with: "\(Double.pi)")
        prepared = prepared.replacingOccurrences(of: "e", with: "\(M_E)")

        // Percentages: "200 * 15%" -> "200 * (15/100)"
        prepared = prepared.replacingOccurrences(
            of: #"(\d+\.?\d*)\s*%"#, with: "(($1)/100)", options: .regularExpression
        )

        // Factorial: 5! -> 120 (must be an integer)
        while let range = prepared.range(of: #"(\d+)!"#, options: .regularExpression) {
            let match = String(prepared[range])
            let numStr = String(match.dropLast())
            guard let num = Int(numStr), num >= 0, num <= 20 else {
                throw CalcError.invalidExpression
            }
            let factorial = (1...max(1, num)).reduce(1, *)
            prepared.replaceSubrange(range, with: "\(factorial)")
        }

        // Power operator
        while let range = prepared.range(of: #"(\d+\.?\d*)\s*\*\*\s*(\d+\.?\d*)"#, options: .regularExpression) {
            let match = String(prepared[range])
            let parts = match.components(separatedBy: "**")
            guard parts.count == 2,
                  let base = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let exp = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
                throw CalcError.invalidExpression
            }
            prepared.replaceSubrange(range, with: "\(pow(base, exp))")
        }

        // Functions (with balanced parentheses)
        let functions: [(String, (Double) -> Double)] = [
            ("sqrt", { sqrt(max(0, $0)) }), ("sin", sin), ("cos", cos), ("tan", tan),
            ("asin", { asin(max(-1, min(1, $0))) }), ("acos", { acos(max(-1, min(1, $0))) }),
            ("atan", atan), ("log", { log10(max(0.000001, $0)) }),
            ("log2", { log2(max(0.000001, $0)) }), ("ln", { log(max(0.000001, $0)) }),
            ("abs", abs), ("ceil", ceil), ("floor", floor), ("round", round),
        ]
        for (name, fn) in functions {
            while let range = findFunction(name, in: prepared) {
                let match = String(prepared[range])
                guard let parenStart = match.firstIndex(of: "("),
                      let parenEnd = match.lastIndex(of: ")") else { break }
                let argStr = String(match[match.index(after: parenStart)..<parenEnd])
                guard let arg = Double(argStr.trimmingCharacters(in: .whitespaces)) else { break }
                prepared.replaceSubrange(range, with: "\(fn(arg))")
            }
        }

        let nsExpr = NSExpression(format: prepared)
        guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw CalcError.invalidExpression
        }
        return result.doubleValue
    }

    /// Finds a function call with balanced parentheses, avoiding the lazy `.*?` bug.
    private func findFunction(_ name: String, in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: "\(name)(") else { return nil }
        var depth = 0
        var idx = text.index(after: start.upperBound)
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                if depth == 0 { return start.lowerBound..<text.index(after: idx) }
                depth -= 1
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    /// Replaces scientific notation (1e6, 2.5e-3) with decimal form.
    private func replaceScientificNotation(_ text: String) -> String {
        var result = text
        let pattern = #"(\d+\.?\d*)[eE]([+-]?\d+)"#
        while let range = result.range(of: pattern, options: .regularExpression) {
            let match = String(result[range])
            let components = match.components(separatedBy: CharacterSet(charactersIn: "eE"))
            guard components.count == 2,
                  let base = Double(components[0]),
                  let exp = Double(components[1]) else { break }
            result.replaceSubrange(range, with: "\(base * pow(10, exp))")
        }
        return result
    }
}

private enum CalcError: LocalizedError {
    case invalidExpression
    var errorDescription: String? { "Invalid mathematical expression" }
}

// MARK: - Open URL

struct OpenURLTool: Tool {
    static let name = "open_url"
    static let description = "Open a URL in the appropriate system app — browser for http/https, Mail for mailto, Maps for maps, Phone for tel, or FaceTime for facetime. Use when the user asks to open a link, email, map location, or make a call."

    @ToolParam(description: "The URL to open. Supported schemes: http, https, mailto, maps, tel, facetime.")
    var url: String

    func run() async throws -> Any {
        await report(Self.name, params: "{\"url\": \"\(url)\"}")

        guard let nsurl = URL(string: url) else {
            let result: [String: Any] = ["error": "Invalid URL format."]
            await reportResult(Self.name, result)
            return result
        }

        let allowed = ["http", "https", "mailto", "maps", "tel", "facetime"]
        guard let scheme = nsurl.scheme?.lowercased(), allowed.contains(scheme) else {
            let result: [String: Any] = ["error": "Unsupported URL scheme. Allowed: \(allowed.joined(separator: ", "))"]
            await reportResult(Self.name, result)
            return result
        }

        guard await UIApplication.shared.canOpenURL(nsurl) else {
            let result: [String: Any] = ["error": "Cannot open URL: \(url). The app may not be installed."]
            await reportResult(Self.name, result)
            return result
        }

        let opened = await MainActor.run { UIApplication.shared.open(nsurl) }
        let result: [String: Any] = ["opened": opened, "url": url]
        await reportResult(Self.name, result)
        return result
    }
}

// MARK: - Wikipedia

struct WikipediaTool: Tool {
    static let name = "wikipedia"
    static let description = """
        Search Wikipedia for articles and get summaries. \
        Use to look up facts, definitions, biographies, historical events, and general knowledge. \
        Two modes: "search" returns article titles and snippets; "extract" returns the summary of a specific article. \
        Language defaults to "en" (English). Use fullExtract=true for the full article instead of just the intro.
        """

    @ToolParam(description: "The search query or article title.")
    var query: String

    @ToolParam(description: #"Either "search" to find matching articles, or "extract" to get a summary of a specific article."#)
    var mode: String = "search"

    @ToolParam(description: "Language code (e.g. 'en', 'ru', 'de', 'fr'). Default 'en'.")
    var language: String = "en"

    @ToolParam(description: "Maximum search results (1-10). Default 5. Only applies to 'search' mode.")
    var maxResults: Int = 5

    @ToolParam(description: "Return the full article instead of just the intro paragraph. Only applies to 'extract' mode. Default false.")
    var fullExtract: Bool = false

    func run() async throws -> Any {
        await report(Self.name, params: "{\"query\": \"\(query)\", \"mode\": \"\(mode)\", \"language\": \"\(language)\", \"maxResults\": \(maxResults), \"fullExtract\": \(fullExtract)}")

        let lang = language.isEmpty ? "en" : language
        let base = "https://\(lang).wikipedia.org"

        let result: [String: Any]
        if mode == "extract" {
            result = try await extractPage(query: query, baseURL: base, fullExtract: fullExtract)
        } else {
            result = try await searchArticles(query: query, baseURL: base, maxResults: maxResults)
        }
        await reportResult(Self.name, result)
        return result
    }

    private func searchArticles(query: String, baseURL: String, maxResults: Int) async throws -> [String: Any] {
        let clamped = max(1, min(maxResults, 10))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "\(baseURL)/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&srlimit=\(clamped)&srprop=snippet"
        guard let url = URL(string: urlStr) else { return ["error": "Failed to build search URL"] }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
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
            snippet = snippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            snippet = HTMLEntityDecoder.decode(snippet)
            return [
                "title": title,
                "snippet": snippet,
                "url": "\(baseURL)/wiki/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)",
            ]
        }
        return ["query": query, "results": results]
    }

    private func extractPage(query: String, baseURL: String, fullExtract: Bool) async throws -> [String: Any] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let exintroParam = fullExtract ? "" : "&exintro=true"
        let urlStr = "\(baseURL)/w/api.php?action=query&titles=\(encoded)&prop=extracts\(exintroParam)&explaintext=true&format=json&redirects=1"
        guard let url = URL(string: urlStr) else { return ["error": "Failed to build extract URL"] }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryResult = json["query"] as? [String: Any],
              let pages = queryResult["pages"] as? [String: [String: Any]] else {
            return ["error": "Failed to parse page data"]
        }

        // Check for disambiguation first
        if let (_, page) = pages.first, let pageID = page["pageid"] as? Int, pageID < 0 {
            return ["error": "Disambiguation page. Try a more specific title or use mode: 'search' first.",
                    "disambiguation": true]
        }

        for (_, page) in pages {
            if let extract = page["extract"] as? String {
                let title = page["title"] as? String ?? query
                let pageID = page["pageid"] as? Int ?? 0
                return ["title": title, "page_id": pageID, "extract": extract,
                        "url": "\(baseURL)/wiki/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)"]
            }
        }
        return ["error": "Page not found. Try a different title or use mode: 'search' first."]
    }
}

// MARK: - Device Info

struct DeviceInfoTool: Tool {
    static let name = "get_device_info"
    static let description = "Get information about this device: real model name, OS version, battery level, available storage, memory, and uptime. Use when the user asks about their device."

    func run() async throws -> Any {
        await report(Self.name, params: "{}")

        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = false }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let processInfo = ProcessInfo.processInfo

        let result: [String: Any] = [
            "device_name": device.name,
            "device_model": device.model,
            "device_model_identifier": Self.deviceModelIdentifier(),
            "system_name": device.systemName,
            "system_version": device.systemVersion,
            "battery_level": Int(device.batteryLevel * 100),
            "battery_state": batteryStateString(device.batteryState),
            "total_storage": totalDiskSpace().map { formatter.string(fromByteCount: $0) } ?? "unknown",
            "free_storage": freeDiskSpace().map { formatter.string(fromByteCount: $0) } ?? "unknown",
            "physical_memory_gb": String(format: "%.1f", Double(processInfo.physicalMemory) / 1_073_741_824),
            "processor_count": processInfo.processorCount,
            "uptime_seconds": Int(processInfo.systemUptime),
            "is_low_power_mode": processInfo.isLowPowerModeEnabled,
        ]
        await reportResult(Self.name, result)
        return result
    }

    /// Returns the real device model identifier (e.g. "iPhone18,1").
    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
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
              let total = attrs[.systemSize] as? Int64 else { return nil }
        return total
    }
    private func freeDiskSpace() -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else { return nil }
        return free
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

    @ToolParam(description: "If true, skip GPS and use IP-based location only (faster, less accurate). Default false.")
    var ipOnly: Bool = false

    func run() async throws -> Any {
        await report(Self.name, params: ipOnly ? "{\"ipOnly\": true}" : "{}")

        let loc: LocationResult
        if ipOnly {
            loc = try await LocationService.shared.ip()
        } else {
            loc = try await LocationService.shared.best()
        }
        let result: [String: Any] = [
            "source": loc.source,
            "latitude": loc.latitude,
            "longitude": loc.longitude,
            "altitude_m": loc.altitude,
            "horizontal_accuracy_m": loc.horizontalAccuracy,
            "location_name": loc.name,
        ]
        await reportResult(Self.name, result)
        return result
    }
}

// MARK: - Weather

struct WeatherTool: Tool {
    static let name = "weather"
    static let description = """
        Call when user asks about weather, temperature, forecast, rain, snow, wind, humidity, or climate. \
        Returns current conditions and multi-day forecast from Open-Meteo (free, no API key). \
        If no city provided, auto-detects your GPS location.
        """

    @ToolParam(description: "City name (e.g. 'London', 'Tokyo', 'Moscow'). Leave empty to auto-detect your location.")
    var city: String = ""

    @ToolParam(description: "Number of forecast days (1-7). Default 7 for a full week forecast.")
    var days: Int = 7

    func run() async throws -> Any {
        let clampedDays = max(1, min(days, 7))
        await report(Self.name, params: city.isEmpty ? "{\"city\": \"(auto-detected)\", \"days\": \(clampedDays)}" : "{\"city\": \"\(city)\", \"days\": \(clampedDays)}")

        let coords: Coords
        if city.isEmpty {
            let loc = try await LocationService.shared.best()
            coords = Coords(lat: loc.latitude, lon: loc.longitude, name: loc.name)
        } else {
            coords = try await geocode(city: city)
        }
        let result = try await fetchWeather(lat: coords.lat, lon: coords.lon, cityName: coords.name, days: clampedDays)
        await reportResult(Self.name, result)
        return result
    }

    private struct Coords { let lat: Double; let lon: Double; let name: String }

    private func geocode(city: String) async throws -> Coords {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlStr = "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json"
        guard let url = URL(string: urlStr) else { throw WeatherError.geocodeFailed }
        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], let first = results.first,
              let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
            throw WeatherError.cityNotFound
        }
        let name = (first["name"] as? String) ?? city
        let country = first["country"] as? String
        return Coords(lat: lat, lon: lon, name: country.map { "\(name), \($0)" } ?? name)
    }

    private func fetchWeather(lat: Double, lon: Double, cityName: String, days: Int) async throws -> [String: Any] {
        let dailyParams = "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code,sunrise,sunset"
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,is_day&daily=\(dailyParams)&timezone=auto&forecast_days=\(days)"
        guard let url = URL(string: urlStr) else { throw WeatherError.fetchFailed }
        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any] else { throw WeatherError.fetchFailed }

        let temp = current["temperature_2m"] as? Double ?? 0
        let feelsLike = current["apparent_temperature"] as? Double ?? temp
        let isDay = (current["is_day"] as? Int ?? 1) == 1

        var result: [String: Any] = [
            "city": cityName,
            "temperature_c": temp,
            "feels_like_c": feelsLike,
            "humidity_percent": current["relative_humidity_2m"] as? Int ?? 0,
            "wind_speed_kmh": current["wind_speed_10m"] as? Double ?? 0,
            "wind_direction_deg": current["wind_direction_10m"] as? Int ?? 0,
            "conditions": weatherDesc(current["weather_code"] as? Int ?? 0, isDay),
            "is_day": isDay,
        ]

        if let daily = json["daily"] as? [String: Any] {
            let dates = daily["time"] as? [String] ?? []
            let highs = daily["temperature_2m_max"] as? [Double] ?? []
            let lows = daily["temperature_2m_min"] as? [Double] ?? []
            let precipProbs = daily["precipitation_probability_max"] as? [Int] ?? []
            let weatherCodes = daily["weather_code"] as? [Int] ?? []
            let sunrises = daily["sunrise"] as? [String] ?? []
            let sunsets = daily["sunset"] as? [String] ?? []

            var forecast: [[String: Any]] = []
            for i in 0..<dates.count {
                var day: [String: Any] = [
                    "date": formatDateHuman(dates[i]),
                    "date_iso": dates[i],
                    "high_c": i < highs.count ? highs[i] : 0,
                    "low_c": i < lows.count ? lows[i] : 0,
                    "precipitation_chance_percent": i < precipProbs.count ? precipProbs[i] : 0,
                    "conditions": i < weatherCodes.count ? weatherDesc(weatherCodes[i], true) : "Unknown",
                ]
                if i < sunrises.count { day["sunrise"] = sunrises[i] }
                if i < sunsets.count { day["sunset"] = sunsets[i] }
                forecast.append(day)
            }
            if let firstSunrise = sunrises.first { result["sunrise"] = firstSunrise }
            if let firstSunset = sunsets.first { result["sunset"] = firstSunset }
            result["forecast"] = forecast
        }
        return result
    }


    /// Converts ISO date to human-readable format (e.g. "2026-07-20" → "Jul 20").
    private func formatDateHuman(_ iso: String) -> String {
        let fmtr = DateFormatter()
        fmtr.locale = Locale(identifier: "en_US_POSIX")
        fmtr.dateFormat = "yyyy-MM-dd"
        guard let date = fmtr.date(from: String(iso.prefix(10))) else { return iso }
        fmtr.dateFormat = "MMM d"
        return fmtr.string(from: date)
    }
    private func weatherDesc(_ code: Int, _ isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "Clear sky" : "Clear night"
        case 1,2,3: return isDay ? "Partly cloudy" : "Partly cloudy"
        case 45,48: return "Foggy"
        case 51,53,55: return "Drizzle"; case 56,57: return "Freezing drizzle"
        case 61,63,65: return "Rain"; case 66,67: return "Freezing rain"
        case 71,73,75: return "Snow"; case 77: return "Snow grains"
        case 80,81,82: return "Rain showers"; case 85,86: return "Snow showers"
        case 95: return "Thunderstorm"; case 96,99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }
}

private enum WeatherError: LocalizedError {
    case geocodeFailed, cityNotFound, fetchFailed
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
        Call when user asks to be reminded, set a reminder, alarm, or notification. \
        Creates a reminder in the system Reminders app. \
        Date can be ISO 8601 (e.g. "2026-07-17T18:00:00") or relative \
        (e.g. "tomorrow 10am", "in 30 minutes", "next Friday 3pm").
        """

    @ToolParam(description: "The reminder title — what to remind about.")
    var title: String

    @ToolParam(description: "Optional notes or details for the reminder.")
    var notes: String?

    @ToolParam(description: #"Due date. ISO 8601 (e.g. "2026-07-17T18:00:00") or relative (e.g. "tomorrow 10am", "in 30 minutes", "next Friday"). If not provided, creates a reminder without a due date."#)
    var dueDate: String?

    @ToolParam(description: "Priority: 0=none, 1=low, 5=medium, 9=high. Default 0.")
    var priority: Int = 0


    func run() async throws -> Any {
        await report(Self.name, params: "{\"title\": \"\(title)\"\(notes.map { ", \"notes\": \"\($0)\"" } ?? "")\(dueDate.map { ", \"dueDate\": \"\($0)\"" } ?? "")}")

        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }
        guard granted else {
            let result: [String: Any] = ["success": false, "error": "FAILED: Reminders access denied. The user must enable Reminders in Settings > Privacy > Reminders."]
            await reportResult(Self.name, result)
            return result
        }

        let parsedDate: Date?
        if let dueDate {
            parsedDate = Self.parseDate(dueDate)
        } else {
            parsedDate = nil
        }

        return try await MainActor.run {
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            if let notes, !notes.isEmpty { reminder.notes = notes }
            if let parsedDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: parsedDate
                )
            }
            reminder.calendar = store.defaultCalendarForNewReminders()
            let clampedPriority = max(0, min(priority, 9))
            reminder.priority = clampedPriority

            do {
                try store.save(reminder, commit: true)
                let result: [String: Any] = [
                    "status": "created",
                    "title": title,
                    "due_date": dueDate as Any,
                    "priority": clampedPriority,
                    "reminder_id": reminder.calendarItemIdentifier,
                ]
                Task { await reportResult(Self.name, result) }
                return result
            } catch {
                let result: [String: Any] = ["error": "Failed to save reminder: \(error.localizedDescription)"]
                Task { await reportResult(Self.name, result) }
                return result
            }
        }
    }

    // MARK: - Date Parsing

    /// Parses ISO 8601 and common relative date expressions.
    private static func parseDate(_ raw: String) -> Date? {
        // 1. ISO 8601 with fractional seconds
        let fmtr = ISO8601DateFormatter()
        fmtr.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmtr.date(from: raw) { return date }
        // 2. ISO 8601 without fractional seconds
        let fmtr2 = ISO8601DateFormatter()
        fmtr2.formatOptions = [.withInternetDateTime]
        if let date = fmtr2.date(from: raw) { return date }

        // 3. Relative date patterns
        let now = Date()
        let cal = Calendar.current
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)

        // "in N minutes/hours/days"
        let inPattern = try? NSRegularExpression(
            pattern: #"^in\s+(\d+)\s+(minute|minutes|hour|hours|day|days|week|weeks|month|months)$"#,
            options: .caseInsensitive
        )
        if let match = inPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(match.range(at: 1), in: lower),
           let unitRange = Range(match.range(at: 2), in: lower),
           let num = Int(lower[numRange]) {
            let unit = String(lower[unitRange])
            let components: DateComponents
            switch unit {
            case "minute", "minutes": components = DateComponents(minute: num)
            case "hour", "hours": components = DateComponents(hour: num)
            case "day", "days": components = DateComponents(day: num)
            case "week", "weeks": components = DateComponents(day: num * 7)
            case "month", "months": components = DateComponents(month: num)
            default: return nil
            }
            return cal.date(byAdding: components, to: now)
        }

        // "tomorrow", "tomorrow 10am", "tomorrow 3pm"
        if lower.hasPrefix("tomorrow") {
            var base = cal.date(byAdding: .day, value: 1, to: now) ?? now
            base = cal.startOfDay(for: base)
            if let time = extractTime(from: raw) {
                base = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base) ?? base
            }
            return base
        }

        // "today 10am", "today 3pm"
        if lower.hasPrefix("today") {
            var base = cal.startOfDay(for: now)
            if let time = extractTime(from: raw) {
                base = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base) ?? base
            }
            return base
        }

        // "next monday", "next friday 2pm"
        let nextPattern = try? NSRegularExpression(
            pattern: #"^next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#,
            options: .caseInsensitive
        )
        if let match = nextPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let dayRange = Range(match.range(at: 1), in: lower) {
            let dayName = String(lower[dayRange])
            if let target = nextWeekday(named: dayName, from: now) {
                if let time = extractTime(from: raw) {
                    return cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: target)
                }
                return target
            }
        }

        // "at 10am", "at 3:30pm", "10:00", "3pm"
        if let time = extractTime(from: raw) {
            return cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now)
        }

        // "10am", "3pm" (bare time)
        if let time = extractTime(from: raw) {
            return cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now)
        }

        return nil
    }

    /// Extracts (hour, minute) from strings like "10am", "3:30pm", "14:00".
    private static func extractTime(from raw: String) -> (hour: Int, minute: Int)? {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)

        // "10:30am", "3:30pm", "14:00"
        let hhmmPattern = try? NSRegularExpression(
            pattern: #"(\d{1,2}):(\d{2})\s*(am|pm)?"#,
            options: .caseInsensitive
        )
        if let match = hhmmPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let hRange = Range(match.range(at: 1), in: lower),
           let mRange = Range(match.range(at: 2), in: lower),
           let hour = Int(lower[hRange]), let minute = Int(lower[mRange]) {
            let ampmRange = match.range(at: 3)
            let isPM = ampmRange.location != NSNotFound
                && String(lower[Range(ampmRange, in: lower)!]) == "pm"
            let adjustedHour: Int
            if isPM && hour < 12 { adjustedHour = hour + 12 }
            else if !isPM && hour == 12 { adjustedHour = 0 }
            else { adjustedHour = hour }
            return (adjustedHour, minute)
        }

        // "10am", "3pm"
        let hPattern = try? NSRegularExpression(
            pattern: #"(\d{1,2})\s*(am|pm)"#,
            options: .caseInsensitive
        )
        if let match = hPattern?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let hRange = Range(match.range(at: 1), in: lower),
           let hour = Int(lower[hRange]) {
            let ampmRange = match.range(at: 2)
            let isPM = ampmRange.location != NSNotFound
                && String(lower[Range(ampmRange, in: lower)!]) == "pm"
            let adjustedHour: Int
            if isPM && hour < 12 { adjustedHour = hour + 12 }
            else if !isPM && hour == 12 { adjustedHour = 0 }
            else { adjustedHour = hour }
            return (adjustedHour, 0)
        }

        return nil
    }

    /// Returns the date of the next occurrence of a weekday.
    private static func nextWeekday(named: String, from date: Date) -> Date? {
        let cal = Calendar.current
        let target: Int
        switch named {
        case "sunday": target = 1
        case "monday": target = 2
        case "tuesday": target = 3
        case "wednesday": target = 4
        case "thursday": target = 5
        case "friday": target = 6
        case "saturday": target = 7
        default: return nil
        }
        var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = target
        guard var result = cal.date(from: components) else { return nil }
        if result <= date {
            result = cal.date(byAdding: .day, value: 7, to: result) ?? result
        }
        return cal.startOfDay(for: result)
    }
}
