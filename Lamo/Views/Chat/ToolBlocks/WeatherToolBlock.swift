import SwiftUI

// MARK: - Weather

struct WeatherCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "temperature_c", "feels_like_c", "humidity_percent", "wind_speed_kmh",
        "wind_direction_deg", "conditions", "is_day", "city", "sunrise", "sunset", "forecast"
    ])

    var body: some View {
        let temp = d["temperature_c"] as? Double ?? 0
        let feels = d["feels_like_c"] as? Double ?? temp
        let hum = d["humidity_percent"] as? Int ?? 0
        let wind = d["wind_speed_kmh"] as? Double ?? 0
        let cond = d["conditions"] as? String ?? ""
        let isDay = d["is_day"] as? Bool ?? true
        let city = d["city"] as? String ?? ""

        VStack(alignment: .leading, spacing: 8) {
            // Hero row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(city)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(cond)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(temp))")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Text("°C")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(weatherEmoji(cond, isDay: isDay))
                    .font(.largeTitle)
            }

            // Metrics row
            HStack(spacing: 20) {
                metricPill(icon: "humidity.fill", value: "\(hum)%", color: .blue)
                metricPill(icon: "wind", value: "\(Int(wind)) km/h", color: .teal)
                metricPill(icon: "thermometer.medium", value: "\(Int(feels))°", color: .orange,
                           label: "feels")
            }

            // Sunrise / sunset
            if let sr = d["sunrise"] as? String, let ss = d["sunset"] as? String {
                HStack(spacing: 16) {
                    Label(shortTime(sr), systemImage: "sunrise.fill")
                        .font(.caption2).foregroundStyle(.orange.opacity(0.8))
                    Label(shortTime(ss), systemImage: "sunset.fill")
                        .font(.caption2).foregroundStyle(.indigo.opacity(0.7))
                }
            }

            // Forecast
            if let forecast = d["forecast"] as? [[String: Any]], !forecast.isEmpty {
                Color.white.opacity(0.06).frame(height: 1)
                ForEach(Array(forecast.enumerated()), id: \.offset) { i, day in
                    let high = day["high_c"] as? Double ?? 0
                    let low = day["low_c"] as? Double ?? 0
                    let precip = day["precipitation_chance_percent"] as? Int ?? 0
                    let fcCond = day["conditions"] as? String ?? ""
                    let dateLabel = i == 0 ? "Today"
                        : shortDate(day["date"] as? String ?? "")
                    HStack(spacing: 8) {
                        Text(dateLabel)
                            .font(.caption2).foregroundStyle(i == 0 ? .primary : .secondary)
                            .frame(width: 40, alignment: .leading)
                        Text(weatherEmoji(fcCond, isDay: true)).font(.caption2)
                        Text(fcCond)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if precip > 0 {
                            Text("💧\(precip)%")
                                .font(.system(size: 9)).foregroundStyle(.blue.opacity(0.7))
                        }
                        Text("\(Int(high))°")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary).frame(width: 30, alignment: .trailing)
                        Text("\(Int(low))°")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.tertiary).frame(width: 30, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }

            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
