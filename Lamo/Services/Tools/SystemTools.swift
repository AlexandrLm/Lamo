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


// MARK: - Calculator

struct CalculatorTool: Tool {
    static let name = "calculator"
    static let description = "Evaluate math expressions. Supports +, -, *, /, %, **, sqrt, sin, cos, log, abs, round, pi, e."

    @ToolParam(description: "Math expression to evaluate.")
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


// MARK: - Wikipedia

struct WikipediaTool: Tool {
    static let name = "wikipedia"
    static let description = "Search Wikipedia articles or get article summaries."

    @ToolParam(description: "Search query or article title.")
    var query: String

    @ToolParam(description: "\"search\" or \"extract\".")
    var mode: String = "search"

    @ToolParam(description: "Wikipedia language code.")
    var language: String = "en"

    @ToolParam(description: "Max search results (1-10).")
    var maxResults: Int = 5

    @ToolParam(description: "Return full article text.")
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


// MARK: - Get Location (CoreLocation)

struct GetLocationTool: Tool {
    static let name = "get_location"
    static let description = "Get GPS or IP-based current location (city, coordinates)."

    @ToolParam(description: "Use IP only (faster, less accurate).")
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
    static let description = "Get current weather and multi-day forecast for any city."

    @ToolParam(description: "City name. Empty for auto-detect.")
    var city: String = ""

    @ToolParam(description: "Forecast days (1-7).")
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

