import Foundation
import LiteRTLM
import UIKit
import EventKit
import CoreLocation



// MARK: - Get Location (CoreLocation)

struct GetLocationTool: Tool {
    static let name = ToolDefinitions.GetLocation.name
    static let description = ToolDefinitions.GetLocation.description

    @ToolParam(description: "Set true for faster, less accurate IP-based location (also works when GPS permission is denied).")
    var ipOnly: Bool = false

    func run() async throws -> Any {
        let paramsStr = ToolReportHelper.paramsJSONString(ipOnly ? ["ipOnly": true] : [:])
        await ToolCallReporter.shared.reportCall(name: Self.name, params: paramsStr)
        if let notice = await AgenticLoopBudget.shared.softStopNotice() {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: notice)
            return notice
        }

        do {
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
            let limited = await AgenticLoopBudget.shared.limitResult(result)
            await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
            return limited
        } catch {
            let err: [String: Any] = [
                "error": String(localized: "Location unavailable: \(error.localizedDescription)"),
                "hint": "Ask the user to enable Location Services, or retry once with the IP-only option. If it keeps failing, ask the user where they are.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }
    }
}

// MARK: - Weather

struct WeatherTool: Tool {
    static let name = ToolDefinitions.Weather.name
    static let description = ToolDefinitions.Weather.description

    @ToolParam(description: "City name (English spelling works best, e.g. 'Berlin', 'New York'). Leave empty to use the device's current location.")
    var city: String = ""

    @ToolParam(description: "Forecast days, 1-7. Use 1-2 for 'today' or 'tomorrow' questions; more only for trip planning.")
    var days: Int = 3

    func run() async throws -> Any {
        let clampedDays = max(1, min(days, 7))
        let paramsStr = ToolReportHelper.paramsJSONString(
            city.isEmpty ? ["city": "(auto-detected)", "days": clampedDays] : ["city": city, "days": clampedDays]
        )
        await ToolCallReporter.shared.reportCall(name: Self.name, params: paramsStr)
        if let notice = await AgenticLoopBudget.shared.softStopNotice() {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: notice)
            return notice
        }

        do {
            let coords: Coords
            if city.isEmpty {
                let loc = try await LocationService.shared.best()
                coords = Coords(lat: loc.latitude, lon: loc.longitude, name: loc.name)
            } else {
                coords = try await geocode(city: city)
            }
            let result = try await fetchWeather(lat: coords.lat, lon: coords.lon, cityName: coords.name, days: clampedDays)
            let limited = await AgenticLoopBudget.shared.limitResult(result)
            await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
            return limited
        } catch WeatherError.cityNotFound {
            let err: [String: Any] = [
                "error": String(localized: "City not found: '\(city)'"),
                "hint": "Check the spelling, use the English city name, or try a larger nearby city.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        } catch {
            let err: [String: Any] = [
                "error": String(localized: "Weather lookup failed: \(error.localizedDescription)"),
                "hint": "The weather service may be unreachable — check the internet connection and retry once. If it keeps failing, say so.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }
    }

    private struct Coords { let lat: Double; let lon: Double; let name: String }

    private func geocode(city: String) async throws -> Coords {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlStr = "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json"
        guard let url = URL(string: urlStr) else { throw WeatherError.geocodeFailed }
        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WeatherError.fetchFailed
        }
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WeatherError.fetchFailed
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any] else { throw WeatherError.fetchFailed }

        let temp = current["temperature_2m"] as? Double ?? 0
        let feelsLike = current["apparent_temperature"] as? Double ?? temp
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        let windDeg = current["wind_direction_10m"] as? Int ?? 0

        var result: [String: Any] = [
            "city": cityName,
            "temperature_c": temp,
            "feels_like_c": feelsLike,
            "humidity_percent": current["relative_humidity_2m"] as? Int ?? 0,
            "wind_speed_kmh": current["wind_speed_10m"] as? Double ?? 0,
            "wind_direction": compassDirection(windDeg),
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

    /// 16-point compass label from degrees — small models read "NW" far better than 315°.
    private func compassDirection(_ degrees: Int) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let idx = ((degrees % 360) + 360) % 360
        return points[(idx * 16 + 180) / 360 % 16]
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
        case .geocodeFailed: return String(localized: "Failed to geocode city name")
        case .cityNotFound: return String(localized: "City not found. Try a more specific name.")
        case .fetchFailed: return String(localized: "Failed to fetch weather data")
        }
    }
}
