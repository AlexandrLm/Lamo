import SwiftUI

// MARK: - Tool Call Block

struct ToolCallBlock: View {
    let call: ToolCallRecord
    let isStreaming: Bool
    @State private var isExpanded = false

    private var accentColor: Color { Color(red: 0.35, green: 0.55, blue: 0.90) }
    private var isRunning: Bool { call.result == nil && isStreaming }
    private var borderColor: Color { isRunning ? accentColor.opacity(0.35) : Color.white.opacity(0.08) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Color.white.opacity(0.06).frame(height: 1).padding(.vertical, 6)
                if let result = call.result {
                    ToolResultView(toolName: call.name, jsonString: result)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(call.params)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                iconView
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isRunning ? .primary : .secondary)
                if isRunning {
                    ProgressView().tint(accentColor).controlSize(.mini).scaleEffect(0.8)
                    Text("running").font(.caption2).foregroundStyle(.tertiary)
                }
                if !isRunning, let result = call.result, !isExpanded {
                    if let summary = resultSummary(from: result) {
                        Text("·").foregroundStyle(.tertiary.opacity(0.4))
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer()
                if call.result != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green.opacity(0.7))
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(
                isRunning
                    ? accentColor
                    : toolColor(name: call.name).opacity(0.6)
            )
    }

    /// One-line result preview for collapsed header.
    private func resultSummary(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        switch call.name {
        case "calculator":
            if let r = dict["result"] as? Double {
                return r == floor(r) && r.isFinite ? "\(Int(r))" : String(format: "%.4g", r)
            }
            if let e = dict["error"] as? String { return "⚠ \(e)" }
        case "weather":
            let t = dict["temperature_c"] as? Double
            let c = dict["conditions"] as? String ?? ""
            return t.map { "\(Int($0))° \(c)" } ?? c
        case "get_current_time":
            return dict["time"] as? String
        case "web_search":
            let results = dict["results"] as? [[String: Any]] ?? []
            return "\(results.count) results"
        case "get_location":
            return (dict["location_name"] ?? dict["display"] ?? dict["city"]) as? String
        case "open_url":
            return (dict["opened"] as? Bool) == true ? "Opened" : "Failed"
        case "create_reminder":
            return dict["title"] as? String
        case "update_memory":
            return (dict["status"] as? String) == "noop" ? "No changes" : "Updated"
        case "fetch_url":
            return dict["title"] as? String
        case "calendar":
            if let events = dict["events"] as? [[String: Any]], !events.isEmpty {
                return "\(events.count) events"
            }
            return dict["mode"] as? String
        case "calendar_availability":
            let count = dict["count"] as? Int ?? 0
            return "\(count) slots"
        case "contacts":
            let count = dict["count"] as? Int ?? 0
            return "\(count) found"
        case "notes":
            return dict["mode"] as? String
        case "code_sandbox":
            if let out = dict["output"] as? String { return String(out.prefix(40)) }
            if dict["error"] != nil { return "Error" }
        case "create_plan":
            let steps = dict["total_steps"] as? Int ?? 0
            return "\(steps) steps"
        default: break
        }
        return nil
    }

    private var icon: String {
        toolIcon(name: call.name)
    }

    private var name: String {
        call.name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Tool Result Router

struct ToolResultView: View {
    let toolName: String; let jsonString: String

    private var parsed: Any? {
        guard let d = jsonString.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    var body: some View {
        switch parsed {
        case let dict as [String: Any]:
            richView(for: dict)
        case let arr as [[String: Any]]:
            arrayView(items: arr)
        case let arr as [Any]:
            arrayView(items: arr.map { ["value": $0] })
        default:
            Text(jsonString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func richView(for d: [String: Any]) -> some View {
        switch toolName {
        case "weather":              WeatherCard(d: d)
        case "web_search":           SearchResults(d: d)
        case "wikipedia":            WikipediaResult(d: d)
        case "calculator":           CalculatorResult(d: d)
        case "get_current_time":     TimeCard(d: d)
        case "get_location":         LocationCard(d: d)
        case "get_device_info":      DeviceCard(d: d)
        case "open_url":             OpenURLResult(d: d)
        case "create_reminder":       ReminderResult(d: d)
        case "update_memory":         MemoryResult(d: d)
        case "fetch_url":            FetchResult(d: d)
        case "calendar":             CalendarCard(d: d)
        case "calendar_availability": CalendarAvailabilityCard(d: d)
        case "contacts":             ContactsCard(d: d)
        case "health":               HealthCard(d: d)
        case "notes":                NotesCard(d: d)
        case "shortcuts":            ShortcutResult(d: d)
        case "code_sandbox":         CodeSandboxCard(d: d)
        case "create_plan":          PlanCard(d: d)
        default:                     PrettyJSON(d: d, title: toolName)
        }
    }

    @ViewBuilder
    private func arrayView(items: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                richView(for: item)
                if i < items.count - 1 {
                    Color.white.opacity(0.06).frame(height: 1).padding(.vertical, 6)
                }
            }
        }
    }
}

// ─── TOOL ICON & COLOR HELPERS ───────────────────────────────────────────

private func toolIcon(name: String) -> String {
    switch name {
    case "web_search":              return "magnifyingglass.circle.fill"
    case "fetch_url":               return "doc.text.magnifyingglass"
    case "get_current_time":        return "clock.fill"
    case "calculator":              return "function"
    case "open_url":                return "safari"
    case "wikipedia":               return "book.pages.fill"
    case "get_location":            return "location.fill"
    case "get_device_info":         return "iphone.gen3"
    case "weather":                 return "cloud.sun.fill"
    case "create_reminder":          return "bell.badge.fill"
    case "update_memory":            return "brain.head.profile"
    case "think":                   return "lightbulb.max.fill"
    case "calendar":                return "calendar"
    case "calendar_availability":    return "calendar.badge.clock"
    case "contacts":                return "person.crop.circle.fill"
    case "health":                  return "heart.fill"
    case "notes":                   return "note.text"
    case "shortcuts":               return "bolt.fill"
    case "code_sandbox":            return "chevron.left.forwardslash.chevron.right"
    case "create_plan":             return "list.bullet.clipboard.fill"
    default:                        return "wrench.fill"
    }
}

private func toolColor(name: String) -> Color {
    switch name {
    case "weather":              return Color(red: 0.30, green: 0.70, blue: 0.95)
    case "calculator":           return Color(red: 0.55, green: 0.40, blue: 0.90)
    case "web_search":           return Color(red: 0.25, green: 0.60, blue: 0.95)
    case "get_current_time":     return Color(red: 0.50, green: 0.65, blue: 0.85)
    case "get_location":         return Color(red: 0.90, green: 0.35, blue: 0.35)
    case "fetch_url":            return Color(red: 0.25, green: 0.70, blue: 0.60)
    case "calendar":             return Color(red: 0.85, green: 0.40, blue: 0.40)
    case "calendar_availability": return Color(red: 0.35, green: 0.65, blue: 0.45)
    case "contacts":             return Color(red: 0.45, green: 0.55, blue: 0.80)
    case "health":               return Color(red: 0.90, green: 0.30, blue: 0.40)
    case "notes":                return Color(red: 0.75, green: 0.65, blue: 0.20)
    case "code_sandbox":         return Color(red: 0.50, green: 0.50, blue: 0.60)
    case "create_plan":          return Color(red: 0.35, green: 0.55, blue: 0.90)
    case "shortcuts":            return Color(red: 0.90, green: 0.55, blue: 0.20)
    default:                     return Color(red: 0.45, green: 0.50, blue: 0.55)
    }
}

// ─── RESULT CARDS ────────────────────────────────────────────────────────

// MARK: - Weather ─────────────────────────────────────────────────────────

private struct WeatherCard: View {
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

private func metricPill(icon: String, value: String, color: Color, label: String? = nil) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color.opacity(0.7))
        Text(value).font(.system(.caption2, design: .rounded).weight(.medium)).foregroundStyle(.primary)
        if let l = label { Text(l).font(.system(size: 9)).foregroundStyle(.tertiary) }
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.08)))
}

// MARK: - Search ──────────────────────────────────────────────────────────

private struct SearchResults: View {
    let d: [String: Any]
    private static let handled = Set(["results", "query"])

    var body: some View {
        let results = d["results"] as? [[String: Any]]
            ?? (d["query"] != nil ? [d] : [])
        let query = d["query"] as? String ?? ""

        VStack(alignment: .leading, spacing: 0) {
            if !query.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                    Text(query).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text("· \(results.count)").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 6)
            }

            ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 8) {
                    // Number badge
                    Text("\(i + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color.white.opacity(0.06))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        if let t = item["title"] as? String, !t.isEmpty {
                            Text(t)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary).lineLimit(2)
                        }
                        if let s = item["snippet"] as? String, !s.isEmpty {
                            Text(s)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        }
                        if let c = item["content"] as? String, !c.isEmpty {
                            Text(String(c.prefix(160)))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary.opacity(0.7)).lineLimit(2)
                        }
                        if let u = item["url"] as? String, !u.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "link").font(.system(size: 8))
                                Text(shortURL(u))
                                    .font(.system(.caption2, design: .monospaced))
                            }
                            .foregroundStyle(.blue.opacity(0.6))
                            .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 6)
                if i < results.count - 1 {
                    Color.white.opacity(0.04).frame(height: 1)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Wikipedia ───────────────────────────────────────────────────────

private struct WikipediaResult: View {
    let d: [String: Any]
    private static let handled = Set(["error", "extract", "title", "page_id", "url", "results", "query"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else if let extract = d["extract"] as? String {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages.fill")
                        .font(.title3).foregroundStyle(.white.opacity(0.3))
                    VStack(alignment: .leading, spacing: 4) {
                        if let t = d["title"] as? String {
                            Text(t)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        Text(extract)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(6)
                        if let url = d["url"] as? String {
                            Text(shortURL(url))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.blue.opacity(0.6))
                        }
                    }
                }
            } else {
                SearchResults(d: d)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Calculator ──────────────────────────────────────────────────────

private struct CalculatorResult: View {
    let d: [String: Any]
    private static let handled = Set(["expression", "error", "result"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let expr = d["expression"] as? String ?? ""
            if let error = d["error"] as? String {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.red.opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(expr)
                            .font(.system(.subheadline, design: .monospaced)).foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                let r = d["result"] as? Double ?? 0
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "function")
                        .font(.title3).foregroundStyle(toolColor(name: "calculator").opacity(0.6))
                    Text(expr)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("=")
                        .font(.title3).foregroundStyle(.tertiary)
                    Text(formatNumber(r))
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Time ────────────────────────────────────────────────────────────

private struct TimeCard: View {
    let d: [String: Any]
    private static let handled = Set(["time", "iso_date", "weekday", "timezone", "utc_offset_hours", "unix_timestamp"])

    var body: some View {
        let time = d["time"] as? String ?? ""
        let wd = d["weekday"] as? String ?? ""
        let date = d["iso_date"] as? String ?? ""
        let tz = d["timezone"] as? String ?? ""

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "clock.fill")
                    .font(.title3).foregroundStyle(toolColor(name: "get_current_time").opacity(0.6))
                Text(time)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(.primary)
                Text(wd)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label(date, systemImage: "calendar")
                    .font(.caption2).foregroundStyle(.secondary)
                Label(tz, systemImage: "globe")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Location ────────────────────────────────────────────────────────

private struct LocationCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "location_name", "display", "city", "region", "country",
        "latitude", "longitude", "altitude_m", "horizontal_accuracy_m", "source", "timezone"
    ])

    var body: some View {
        let name = d["location_name"] as? String
            ?? d["display"] as? String
            ?? d["city"] as? String
            ?? ""
        let lat = d["latitude"] as? Double ?? 0
        let lon = d["longitude"] as? Double ?? 0
        let region = d["region"] as? String
        let country = d["country"] as? String

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3).foregroundStyle(.red.opacity(0.8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.isEmpty ? "Unknown location" : name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    let subtitle = [region, country].compactMap { $0 }.joined(separator: ", ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 16) {
                Label(
                    "\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))",
                    systemImage: "smallcircle.filled.circle"
                ).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                if let alt = d["altitude_m"] as? Double {
                    Label("\(Int(alt))m", systemImage: "mountain.2")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Device Info ─────────────────────────────────────────────────────

private struct DeviceCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "device_name", "device_model", "device_model_identifier",
        "system_name", "system_version", "battery_level", "battery_state",
        "physical_memory_gb", "free_storage", "total_storage",
        "processor_count", "uptime_seconds", "is_low_power_mode"
    ])

    var body: some View {
        let name = d["device_name"] as? String ?? ""
        let model = d["device_model"] as? String ?? ""
        let os = "\(d["system_name"] as? String ?? "") \(d["system_version"] as? String ?? "")"

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(model) · \(os)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "iphone.gen3")
                    .font(.title2).foregroundStyle(.white.opacity(0.2))
            }
            BatteryBar(level: d["battery_level"] as? Int ?? 0)
            StorageBar(free: d["free_storage"] as? String ?? "", total: d["total_storage"] as? String ?? "")
            HStack(spacing: 16) {
                Label(
                    "\(d["physical_memory_gb"] as? String ?? "?") GB RAM",
                    systemImage: "memorychip"
                ).font(.caption2).foregroundStyle(.tertiary)
                Label(
                    "Uptime \(fmtUptime(d["uptime_seconds"] as? Int ?? 0))",
                    systemImage: "clock.arrow.circlepath"
                ).font(.caption2).foregroundStyle(.tertiary)
                if (d["is_low_power_mode"] as? Bool) == true {
                    Label("LPM", systemImage: "battery.25percent")
                        .font(.caption2).foregroundStyle(.yellow)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

private struct BatteryBar: View {
    let level: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: level <= 10 ? "battery.0percent"
                : level <= 25 ? "battery.25percent"
                : "battery.75percent")
                .font(.caption2)
                .foregroundStyle(level <= 10 ? .red : level <= 20 ? .orange : .green)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level <= 10 ? Color.red : level <= 20 ? Color.orange : Color.green)
                        .frame(width: geo.size.width * CGFloat(level) / 100, height: 5)
                }
            }.frame(height: 5)
            Text("\(level)%").font(.caption2).foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private struct StorageBar: View {
    let free: String; let total: String
    var body: some View {
        let fb = parseBytes(free); let tb = parseBytes(total)
        if tb > 0 {
            let frac = CGFloat(tb - fb) / CGFloat(tb)
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.caption2).foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(frac > 0.9 ? Color.orange : Color.white.opacity(0.25))
                            .frame(width: geo.size.width * frac, height: 5)
                    }
                }.frame(height: 5)
                Text("\(free) free / \(total)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Open URL ────────────────────────────────────────────────────────

private struct OpenURLResult: View {
    let d: [String: Any]
    private static let handled = Set(["opened", "url", "error"])

    var body: some View {
        let opened = d["opened"] as? Bool ?? false
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: opened ? "safari" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(opened ? .blue : .red.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(opened ? "Opened in browser" : "Could not open")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(opened ? .primary : Color.orange)
                    Text(shortURL(d["url"] as? String ?? ""))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.blue.opacity(0.6))
                }
            }
            if let err = d["error"] as? String, !opened {
                Text(err).font(.caption2).foregroundStyle(.red.opacity(0.7))
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Reminder ────────────────────────────────────────────────────────

private struct ReminderResult: View {
    let d: [String: Any]
    private static let handled = Set(["error", "status", "title", "due_date", "reminder_id", "notes"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title3).foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d["title"] as? String ?? "Reminder")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        if let due = d["due_date"] as? String {
                            Label(due, systemImage: "calendar")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3).foregroundStyle(.green.opacity(0.7))
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Memory ──────────────────────────────────────────────────────────

private struct MemoryResult: View {
    let d: [String: Any]
    private static let handled = Set(["status", "info", "existing_facts", "stored_facts", "deleted_facts"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let status = d["status"] as? String ?? ""
            let stored = d["stored_facts"] as? [String] ?? []
            let deleted = d["deleted_facts"] as? [String] ?? []
            let existing = d["existing_facts"] as? [String] ?? []

            if status == "noop" {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3).foregroundStyle(.purple.opacity(0.4))
                    Text("No new facts to store")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3).foregroundStyle(.purple.opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memory updated").font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                        if !stored.isEmpty {
                            Text("+\(stored.count) stored").font(.caption2).foregroundStyle(.green.opacity(0.7))
                        }
                        if !deleted.isEmpty {
                            Text("-\(deleted.count) removed").font(.caption2).foregroundStyle(.orange.opacity(0.7))
                        }
                    }
                }
                // Show facts
                ForEach(stored, id: \.self) { fact in
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 8)).foregroundStyle(.green.opacity(0.5))
                        Text(fact).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.leading, 4)
                }
                ForEach(existing.prefix(3), id: \.self) { fact in
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
                        Text(fact).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Fetch URL ───────────────────────────────────────────────────────

private struct FetchResult: View {
    let d: [String: Any]
    private static let handled = Set(["title", "content", "url", "source", "description", "type"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3).foregroundStyle(toolColor(name: "fetch_url").opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    if let t = d["title"] as? String, !t.isEmpty {
                        Text(t)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(shortURL(d["url"] as? String ?? ""))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.blue.opacity(0.6))
                        if let type = d["type"] as? String {
                            Text("· \(type)").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if (d["source"] as? String) == "cache" {
                            Text("· cached").font(.caption2).foregroundStyle(.green.opacity(0.6))
                        }
                    }
                }
            }
            if let desc = d["description"] as? String, !desc.isEmpty {
                Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            if let c = d["content"] as? String, !c.isEmpty {
                Text(String(c.prefix(200)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary.opacity(0.7)).lineLimit(4)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Calendar ────────────────────────────────────────────────────────

private struct CalendarCard: View {
    let d: [String: Any]
    private static let handled = Set(["mode", "events", "event", "error", "query", "count", "action"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else if let events = d["events"] as? [[String: Any]], !events.isEmpty {
                headerRow(icon: "calendar", color: toolColor(name: "calendar"),
                          title: "\(events.count) event\(events.count == 1 ? "" : "s")",
                          subtitle: d["mode"] as? String)

                ForEach(Array(events.enumerated()), id: \.offset) { i, event in
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(toolColor(name: "calendar").opacity(0.5))
                            .frame(width: 3)
                            .cornerRadius(1.5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event["title"] as? String ?? event["summary"] as? String ?? "")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary)
                            if let start = event["start"] as? String {
                                HStack(spacing: 8) {
                                    Label(formatEventTime(start), systemImage: "clock")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    if let end = event["end"] as? String {
                                        Text("→ \(formatEventTime(end))")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            if let loc = event["location"] as? String, !loc.isEmpty {
                                Label(loc, systemImage: "mappin.and.ellipse")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let notes = event["notes"] as? String, !notes.isEmpty {
                                Text(notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                            }
                        }
                    }
                    if i < events.count - 1 {
                        Color.white.opacity(0.04).frame(height: 1).padding(.vertical, 2)
                    }
                }
            } else if let event = d["event"] as? [String: Any] {
                headerRow(icon: "calendar.badge.plus", color: toolColor(name: "calendar"),
                          title: "Event created", subtitle: d["mode"] as? String)
                eventRow(event)
            } else {
                headerRow(icon: "calendar", color: toolColor(name: "calendar"),
                          title: "No events", subtitle: d["mode"] as? String)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }

    private func eventRow(_ event: [String: Any]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle().fill(toolColor(name: "calendar").opacity(0.5)).frame(width: 3).cornerRadius(1.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(event["title"] as? String ?? event["summary"] as? String ?? "")
                    .font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(.primary)
                if let start = event["start"] as? String {
                    Label(formatEventTime(start), systemImage: "clock")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Calendar Availability ───────────────────────────────────────────

private struct CalendarAvailabilityCard: View {
    let d: [String: Any]
    private static let handled = Set(["duration_minutes", "range_start", "range_end", "slots", "count", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let count = d["count"] as? Int ?? 0
                let duration = d["duration_minutes"] as? Int ?? 60
                headerRow(icon: "calendar.badge.clock", color: toolColor(name: "calendar_availability"),
                          title: "\(count) free slot\(count == 1 ? "" : "s")",
                          subtitle: "\(duration)min each")

                if let slots = d["slots"] as? [[String: Any]], !slots.isEmpty {
                    ForEach(Array(slots.prefix(8).enumerated()), id: \.offset) { i, slot in
                        HStack(spacing: 8) {
                            Circle().fill(toolColor(name: "calendar_availability").opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(slot["start"] as? String ?? "")
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.primary)
                            Text("→").font(.caption2).foregroundStyle(.tertiary)
                            Text(slot["end"] as? String ?? "")
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    if slots.count > 8 {
                        Text("… and \(slots.count - 8) more")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Contacts ────────────────────────────────────────────────────────

private struct ContactsCard: View {
    let d: [String: Any]
    private static let handled = Set(["query", "count", "contacts", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let contacts = d["contacts"] as? [[String: Any]] ?? []
                let count = d["count"] as? Int ?? contacts.count
                headerRow(icon: "person.crop.circle.fill", color: toolColor(name: "contacts"),
                          title: "\(count) contact\(count == 1 ? "" : "s")",
                          subtitle: "query: \(d["query"] as? String ?? "")")

                ForEach(Array(contacts.enumerated()), id: \.offset) { i, contact in
                    HStack(alignment: .top, spacing: 8) {
                        // Avatar circle
                        let initials = ((contact["name"] as? String) ?? "?")
                            .split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
                        Text(initials)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(toolColor(name: "contacts").opacity(0.25)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact["name"] as? String ?? "")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary)
                            if let org = contact["organization"] as? String {
                                Text(org).font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let phones = contact["phones"] as? [String] {
                                ForEach(phones, id: \.self) { phone in
                                    Label(phone, systemImage: "phone.fill")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                            if let emails = contact["emails"] as? [String] {
                                ForEach(emails, id: \.self) { email in
                                    Label(email, systemImage: "envelope.fill")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.blue.opacity(0.6))
                                }
                            }
                        }
                    }
                    if i < contacts.count - 1 {
                        Color.white.opacity(0.04).frame(height: 1).padding(.vertical, 2)
                    }
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Health ──────────────────────────────────────────────────────────

private struct HealthCard: View {
    let d: [String: Any]
    private static let handled = Set(["mode", "days", "data", "error", "metric"])

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let mode = d["mode"] as? String ?? ""
                let days = d["days"] as? Int ?? 1
                headerRow(icon: "heart.fill", color: toolColor(name: "health"),
                          title: mode.replacingOccurrences(of: "_", with: " ").capitalized,
                          subtitle: days == 1 ? "Today" : "Last \(days) days")

                if let data = d["data"] as? [String: Any] {
                    switch mode {
                    case "steps":
                        if let steps = data["steps"] as? Int {
                            healthStat(value: "\(steps)", unit: "steps",
                                       icon: "figure.walk", color: .green)
                        }
                    case "heart_rate":
                        if let hr = data["avg_bpm"] as? Double {
                            healthStat(value: "\(Int(hr))", unit: "bpm",
                                       icon: "heart.fill", color: .red)
                        }
                        if let minBpm = data["min_bpm"] as? Double,
                           let maxBpm = data["max_bpm"] as? Double {
                            HStack(spacing: 12) {
                                Label("\(Int(minBpm)) min", systemImage: "arrow.down")
                                Label("\(Int(maxBpm)) max", systemImage: "arrow.up")
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                    case "sleep":
                        if let hours = data["hours"] as? Double {
                            healthStat(value: String(format: "%.1f", hours), unit: "hours",
                                       icon: "moon.zzz.fill", color: .indigo)
                        }
                        if let start = data["start"] as? String, let end = data["end"] as? String {
                            HStack(spacing: 12) {
                                Label(shortTime(start), systemImage: "bed.double.fill")
                                Label(shortTime(end), systemImage: "alarm.fill")
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                    case "weight":
                        if let kg = data["weight_kg"] as? Double {
                            healthStat(value: String(format: "%.1f", kg), unit: "kg",
                                       icon: "scalemass.fill", color: .teal)
                        }
                        if let date = data["date"] as? String {
                            Text(date).font(.caption2).foregroundStyle(.tertiary)
                        }
                    case "summary":
                        summaryGrid(data: data)
                    default:
                        genericHealthData(data: data)
                    }
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }

    private func healthStat(value: String, unit: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(.primary)
                Text(unit)
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }

    private func summaryGrid(data: [String: Any]) -> some View {
        let items: [(String, String, String, Color)] = [
            ("figure.walk", "\(data["steps"] as? Int ?? 0)", "steps", .green),
            ("heart.fill", "\(data["avg_bpm"] as? Int ?? data["heart_rate"] as? Int ?? 0)", "bpm", .red),
            ("moon.zzz.fill", "\(String(format: "%.1f", data["hours"] as? Double ?? data["sleep_hours"] as? Double ?? 0))", "hrs", .indigo),
            ("scalemass.fill", "\(String(format: "%.1f", data["weight_kg"] as? Double ?? 0))", "kg", .teal),
        ]
        return VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(items, id: \.0) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.0).font(.caption).foregroundStyle(item.3)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.1).font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.2).font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                }
            }
        }
    }

    private func genericHealthData(data: [String: Any]) -> some View {
        ForEach(Array(data.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
            HStack {
                Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(describing: value))
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Notes ───────────────────────────────────────────────────────────

private struct NotesCard: View {
    let d: [String: Any]
    private static let handled = Set(["mode", "count", "notes", "note", "title", "action", "deleted", "error", "query"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let mode = d["mode"] as? String ?? ""
                switch mode {
                case "list", "search":
                    let notes = d["notes"] as? [[String: Any]] ?? []
                    let count = d["count"] as? Int ?? notes.count
                    headerRow(icon: "note.text", color: toolColor(name: "notes"),
                              title: "\(count) note\(count == 1 ? "" : "s")",
                              subtitle: mode == "search" ? "query: \(d["query"] as? String ?? "")" : nil)
                    ForEach(Array(notes.prefix(10).enumerated()), id: \.offset) { i, note in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text").font(.caption2).foregroundStyle(toolColor(name: "notes").opacity(0.5))
                            Text(note["title"] as? String ?? "")
                                .font(.caption).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            if let date = note["created_at"] as? String {
                                Text(shortDate(date)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                        if i < notes.count - 1 {
                            Color.white.opacity(0.03).frame(height: 1)
                        }
                    }
                case "read":
                    if let note = d["note"] as? [String: Any] {
                        headerRow(icon: "note.text", color: toolColor(name: "notes"),
                                  title: note["title"] as? String ?? "Note",
                                  subtitle: (note["created_at"] as? String).map { "Created \($0)" })
                        if let content = note["content"] as? String {
                            Text(content)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(8)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                        }
                    }
                case "create":
                    let action = d["action"] as? String ?? "saved"
                    let title = d["title"] as? String ?? "Note"
                    HStack(spacing: 8) {
                        Image(systemName: action == "created" ? "plus.circle.fill" : "pencil.circle.fill")
                            .font(.title3).foregroundStyle(toolColor(name: "notes").opacity(0.7))
                        Text("\(action == "created" ? "Created" : "Updated"): \(title)")
                            .font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(.primary)
                    }
                case "delete":
                    HStack(spacing: 8) {
                        Image(systemName: "trash.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                        Text("Deleted: \(d["title"] as? String ?? "note")")
                            .font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(.primary)
                    }
                default:
                    PrettyJSON(d: d, title: "notes")
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Shortcuts ───────────────────────────────────────────────────────

private struct ShortcutResult: View {
    let d: [String: Any]
    private static let handled = Set(["success", "shortcut", "note", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let success = d["success"] as? Bool ?? false
            let name = d["shortcut"] as? String ?? ""

            HStack(spacing: 8) {
                Image(systemName: success ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3)
                    .foregroundStyle(success ? toolColor(name: "shortcuts") : .red.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(success ? "Shortcut launched" : "Shortcut failed")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(success ? .primary : Color.orange)
                    Text(name)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if let note = d["note"] as? String {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
            if let error = d["error"] as? String {
                Text(error).font(.caption2).foregroundStyle(.red.opacity(0.7))
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Code Sandbox ────────────────────────────────────────────────────

private struct CodeSandboxCard: View {
    let d: [String: Any]
    private static let handled = Set(["output", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let output = d["output"] as? String, !output.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.caption).foregroundStyle(.green.opacity(0.7))
                    Text("Output")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.primary)
                }
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(12)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
                    .textSelection(.enabled)
            }
            if let error = d["error"] as? String, !error.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red.opacity(0.7))
                    Text("Error")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.orange)
                }
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(8)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.08))
                    )
                    .textSelection(.enabled)
            }
            if d["output"] == nil && d["error"] == nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green.opacity(0.6))
                    Text("Executed (no output)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Plan ────────────────────────────────────────────────────────────

private struct PlanCard: View {
    let d: [String: Any]
    private static let handled = Set(["plan_created", "goal", "total_steps", "steps", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let goal = d["goal"] as? String ?? ""
                let total = d["total_steps"] as? Int ?? 0
                let steps = d["steps"] as? [[String: Any]] ?? []

                // Goal header
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.title3).foregroundStyle(toolColor(name: "create_plan").opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(total) step\(total == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // Steps with connector line
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 8) {
                        // Step number + connector
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(toolColor(name: "create_plan").opacity(0.2))
                                    .frame(width: 20, height: 20)
                                Text("\(i + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(toolColor(name: "create_plan"))
                            }
                            if i < steps.count - 1 {
                                Rectangle()
                                    .fill(toolColor(name: "create_plan").opacity(0.15))
                                    .frame(width: 1.5)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: toolIcon(name: step["tool"] as? String ?? ""))
                                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                                Text(step["tool"] as? String ?? "")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.blue.opacity(0.5))
                            }
                            Text(step["description"] as? String ?? "")
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, i < steps.count - 1 ? 8 : 0)
                    }
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Pretty JSON (universal fallback) ────────────────────────────────

private struct PrettyJSON: View {
    let d: [String: Any]
    var title: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 6) {
                    Image(systemName: toolIcon(name: title))
                        .font(.caption).foregroundStyle(toolColor(name: title).opacity(0.5))
                    Text(title.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Color.white.opacity(0.05).frame(height: 1)
            }
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 6
            ) {
                ForEach(Array(d.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    JSONChip(key: key, value: value)
                }
            }
        }
    }
}

private struct JSONChip: View {
    let key: String; let value: Any
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: chipIcon(key)).font(.system(size: 8)).foregroundStyle(.tertiary)
            Text(key.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.blue.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(chipValue(value))
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .foregroundStyle(chipColor(value)).lineLimit(1)
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.05), lineWidth: 0.5))
    }
}

// MARK: - Extra Fields ────────────────────────────────────────────────────

private struct ExtraFields: View {
    let dict: [String: Any]; let handled: Set<String>
    var body: some View {
        let extra = dict.filter { !handled.contains($0.key) }
        if extra.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Color.white.opacity(0.06).frame(height: 1).padding(.vertical, 4)
                FlowLayout(spacing: 5) {
                    ForEach(extra.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 3) {
                            Text(key.replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
                            Text("·").font(.system(size: 8)).foregroundStyle(.tertiary.opacity(0.4))
                            Text(chipValue(value))
                                .font(.system(size: 8, design: .monospaced)).foregroundStyle(chipColor(value))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04)))
                    }
                }
            }
        )
    }
}

// MARK: - Shared Header ───────────────────────────────────────────────────

private func headerRow(icon: String, color: Color, title: String, subtitle: String?) -> some View {
    HStack(spacing: 8) {
        Image(systemName: icon)
            .font(.title3).foregroundStyle(color.opacity(0.7))
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
            if let sub = subtitle {
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Flow Layout ─────────────────────────────────────────────────────

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let h = rows.compactMap { row in row.map { $0.sizeThatFits(.unspecified).height }.max() }.reduce(0, +)
        return CGSize(width: proposal.width ?? 0, height: h + CGFloat(max(0, rows.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for item in row {
                item.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += item.sizeThatFits(.unspecified).width + spacing
            }
            y += rowH + spacing
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentX: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if currentX + sz.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([v]); currentX = sz.width + spacing
            } else {
                rows[rows.count - 1].append(v); currentX += sz.width + spacing
            }
        }
        return rows
    }
}

// ─── HELPERS ─────────────────────────────────────────────────────────────

private func chipIcon(_ key: String) -> String {
    switch key {
    case let k where k.contains("temp"):      return "thermometer.medium"
    case let k where k.contains("humid"):      return "humidity.fill"
    case let k where k.contains("wind"):       return "wind"
    case let k where k.contains("url"):        return "link"
    case let k where k.contains("city") || k.contains("location"): return "mappin.and.ellipse"
    case let k where k.contains("time") || k.contains("date"):    return "clock"
    case let k where k.contains("battery"):    return "battery.75percent"
    case let k where k.contains("storage") || k.contains("disk"): return "internaldrive"
    case let k where k.contains("memory") || k.contains("ram"):   return "memorychip"
    case let k where k.contains("status"):     return "circlebadge"
    case let k where k.contains("error"):      return "xmark.circle"
    case let k where k.contains("name") || k.contains("title"):   return "textformat"
    case let k where k.contains("id"):         return "number"
    case let k where k.contains("count") || k.contains("number"): return "number.circle"
    case let k where k.contains("phone"):      return "phone.fill"
    case let k where k.contains("email"):      return "envelope.fill"
    default:                                    return "circle.fill"
    }
}

private func chipValue(_ value: Any) -> String {
    switch value {
    case let s as String where s.count > 60: return "\"\(s.prefix(60))…\""
    case let s as String:    return s
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): return n.boolValue ? "true" : "false"
    case let n as NSNumber:  return formatNumber(n.doubleValue)
    case is NSNull:          return "—"
    case let arr as [Any]:   return "[\(arr.count)]"
    case let d as [String: Any]: return "{\(d.count)}"
    default:                 return "\(value)"
    }
}

private func chipColor(_ value: Any) -> Color {
    switch value {
    case is String:  return .primary.opacity(0.85)
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
        return n.boolValue ? .green.opacity(0.7) : .orange.opacity(0.7)
    case is NSNumber: return .green.opacity(0.6)
    case is NSNull:   return .secondary
    default:          return .secondary
    }
}

private func fmtUptime(_ s: Int) -> String {
    let h = s / 3600, m = (s % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

private func weatherEmoji(_ c: String, isDay: Bool) -> String {
    let l = c.lowercased()
    if l.contains("clear")                { return isDay ? "☀️" : "🌙" }
    if l.contains("cloud")                { return isDay ? "⛅" : "☁️" }
    if l.contains("fog") || l.contains("mist") { return "🌫️" }
    if l.contains("drizzle")              { return "🌦️" }
    if l.contains("rain") || l.contains("shower") { return "🌧️" }
    if l.contains("snow")                 { return "🌨️" }
    if l.contains("thunder")              { return "⛈️" }
    return "🌡️"
}

private func shortTime(_ iso: String) -> String {
    if let t = iso.firstIndex(of: "T") { return String(String(iso[iso.index(after: t)...]).prefix(5)) }
    return iso
}

private func shortURL(_ u: String) -> String {
    u.replacingOccurrences(of: "https://", with: "")
     .replacingOccurrences(of: "http://", with: "")
     .replacingOccurrences(of: "www.", with: "")
     .components(separatedBy: "/").first ?? u
}

private func formatNumber(_ n: Double) -> String {
    if n == floor(n) && n.isFinite && abs(n) < 1e15 { return String(Int(n)) }
    return String(format: "%.6g", n)
}

private func shortDate(_ iso: String) -> String {
    if iso.count >= 10 { return String(iso.suffix(5)) }; return iso
}

private func formatEventTime(_ iso: String) -> String {
    if let t = iso.firstIndex(of: "T") {
        let timePart = String(iso[iso.index(after: t)...])
        return String(timePart.prefix(5))
    }
    return iso
}

private func parseBytes(_ s: String) -> Int64 {
    let c = s.lowercased().replacingOccurrences(of: ",", with: "")
    if c.hasSuffix("gb") {
        return Int64((Double(c.replacingOccurrences(of: "gb", with: "").trimmingCharacters(in: .whitespaces)) ?? 0) * 1_073_741_824)
    }
    if c.hasSuffix("mb") {
        return Int64((Double(c.replacingOccurrences(of: "mb", with: "").trimmingCharacters(in: .whitespaces)) ?? 0) * 1_048_576)
    }
    return Int64(c) ?? 0
}

// MARK: - Container

struct ToolCallsView: View {
    let calls: [ToolCallRecord]; let isStreaming: Bool
    var body: some View { ForEach(calls) { ToolCallBlock(call: $0, isStreaming: isStreaming) } }
}
