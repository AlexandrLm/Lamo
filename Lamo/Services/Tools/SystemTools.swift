import Foundation
import LiteRTLM
import UIKit
import EventKit
import CoreLocation



// MARK: - Get Location (CoreLocation)

struct GetLocationTool: Tool {
    static let name = "get_location"
    static let description = "Get GPS or IP-based current location (city, coordinates)."

    @ToolParam(description: "Use IP only (faster, less accurate).")
    var ipOnly: Bool = false

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(name: Self.name, params: ipOnly ? "{\"ipOnly\": true}" : "{}")

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
        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
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
        await ToolCallReporter.shared.reportCall(name: Self.name, params: city.isEmpty ? "{\"city\": \"(auto-detected)\", \"days\": \(clampedDays)}" : "{\"city\": \"\(city)\", \"days\": \(clampedDays)}")

        let coords: Coords
        if city.isEmpty {
            let loc = try await LocationService.shared.best()
            coords = Coords(lat: loc.latitude, lon: loc.longitude, name: loc.name)
        } else {
            coords = try await geocode(city: city)
        }
        let result = try await fetchWeather(lat: coords.lat, lon: coords.lon, cityName: coords.name, days: clampedDays)
        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
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

