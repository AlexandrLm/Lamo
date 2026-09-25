import SwiftUI

// MARK: - Weather

struct WeatherCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "city", "temperature_c", "feels_like_c", "humidity_percent",
        "wind_speed_kmh", "wind_direction", "conditions", "is_day",
        "sunrise", "sunset", "forecast"
    ])

    var body: some View {
        let temp = d["temperature_c"] as? Double ?? 0
        let feels = d["feels_like_c"] as? Double ?? temp
        let hum = d["humidity_percent"] as? Int ?? 0
        let wind = d["wind_speed_kmh"] as? Double ?? 0
        let windDir = d["wind_direction"] as? String ?? ""
        let cond = d["conditions"] as? String ?? ""
        let isDay = d["is_day"] as? Bool ?? true
        let city = d["city"] as? String ?? ""

        VStack(alignment: .leading, spacing: 10) {
            // Hero row
            HStack(alignment: .center, spacing: 12) {
                ToolBadge(icon: weatherSymbol(cond, isDay: isDay),
                          tint: weatherSymbolColor(cond, isDay: isDay), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(city)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(cond)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(temp))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("°C")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, -6)
            }

            // Metrics row
            HStack(spacing: 8) {
                metricPill(icon: "humidity.fill", value: "\(hum)%", color: .blue)
                metricPill(icon: "wind", value: String(localized: "\(Int(wind)) km/h"), color: .teal)
                if !windDir.isEmpty {
                    metricPill(icon: "location.north.circle", value: windDir, color: .cyan)
                }
                metricPill(icon: "thermometer.medium", value: "\(Int(feels))°", color: .orange,
                           label: String(localized: "feels"))
            }

            // Sunrise / sunset
            if let sr = d["sunrise"] as? String, let ss = d["sunset"] as? String {
                HStack(spacing: 16) {
                    Label(shortTime(sr), systemImage: "sunrise.fill")
                        .font(.caption2).foregroundStyle(.orange)
                    Label(shortTime(ss), systemImage: "sunset.fill")
                        .font(.caption2).foregroundStyle(.indigo)
                }
            }

            // Forecast with temperature range bars
            if let forecast = d["forecast"] as? [[String: Any]], !forecast.isEmpty {
                ThinDivider()
                let days = forecast.map { day -> (label: String, symbol: String, symColor: Color, precip: Int, high: Double, low: Double) in
                    let high = day["high_c"] as? Double ?? 0
                    let low = day["low_c"] as? Double ?? 0
                    let precip = day["precipitation_chance_percent"] as? Int ?? 0
                    let fcCond = day["conditions"] as? String ?? ""
                    return (shortDate(day["date"] as? String ?? ""), weatherSymbol(fcCond, isDay: true),
                            weatherSymbolColor(fcCond, isDay: true), precip, high, low)
                }
                let weekMin = days.map(\.low).min() ?? 0
                let weekMax = days.map(\.high).max() ?? 1
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    HStack(spacing: 8) {
                        Text(i == 0 ? String(localized: "Today") : day.label)
                            .font(.caption2.weight(i == 0 ? .semibold : .regular))
                            .foregroundStyle(i == 0 ? .primary : .secondary)
                            .frame(width: 52, alignment: .leading)
                        Image(systemName: day.symbol)
                            .font(.caption)
                            .foregroundStyle(day.symColor)
                            .frame(width: 20)
                        Text("\(Int(day.low))°")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 30, alignment: .trailing)
                        rangeBar(low: day.low, high: day.high, min: weekMin, max: weekMax)
                            .frame(maxWidth: .infinity)
                        Text("\(Int(day.high))°")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(width: 30, alignment: .trailing)
                        Text(day.precip > 0 ? "\(day.precip)%" : "")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
                Text("H: \(Int(weekMax))°  L: \(Int(weekMin))°")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }

            FieldGrid(dict: d, handled: Self.handled)
        }
    }

    /// iOS-Weather-style temperature range segment.
    private func rangeBar(low: Double, high: Double, min rangeMin: Double, max rangeMax: Double) -> some View {
        GeometryReader { geo in
            let span = Swift.max(rangeMax - rangeMin, 0.5)
            let x0 = CGFloat((low - rangeMin) / span) * geo.size.width
            let w = Swift.max(CGFloat((high - low) / span) * geo.size.width, 5)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(
                        colors: [.blue, .teal, .yellow, .orange],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: w, height: 4)
                    .offset(x: x0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 10)
    }
}
