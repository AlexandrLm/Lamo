import SwiftUI

// MARK: - Tool Call Block

struct ToolCallBlock: View {
    let call: ToolCallRecord
    let isStreaming: Bool
    @State private var isExpanded = false
    @State private var cachedSummary: String?

    private var accentColor: Color { LamoTheme.Colors.accent }
    private var isRunning: Bool { call.result == nil && isStreaming }

    private var hasError: Bool {
        guard let data = call.result?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? String else { return false }
        return !error.isEmpty
    }

    /// Icon tint encodes state: brand accent = running, red = failed, tool color = done.
    private var statusTint: Color {
        if isRunning { return accentColor }
        if hasError { return LamoTheme.Colors.error }
        return toolColor(name: call.name)
    }

    private var borderColor: Color {
        if isRunning { return accentColor.opacity(0.5) }
        if hasError { return LamoTheme.Colors.error.opacity(0.35) }
        return toolColor(name: call.name).opacity(0.22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                ThinDivider().padding(.vertical, 8)
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
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .onAppear { cachedSummary = call.result.flatMap { resultSummary(from: $0) } }
        .onChange(of: call.result) { _, new in cachedSummary = new.flatMap { resultSummary(from: $0) } }
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                ToolBadge(icon: icon, tint: statusTint, size: 26)
                    .symbolEffect(.breathe, value: isRunning)
                Text(name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(isRunning ? .primary : .secondary)
                if isRunning {
                    ProgressView().controlSize(.mini).tint(accentColor)
                    Text("Running").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if !isRunning, call.result != nil, !isExpanded, let summary = cachedSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One-line result preview for collapsed header.
    private func resultSummary(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        // web_search returns a bare array; everything else returns a dict.
        if call.name == "web_search" {
            if let arr = parsed as? [[String: Any]] {
                return String(localized: "^[\(arr.count) result](inflect: true)")
            }
            if let dict = parsed as? [String: Any],
               let results = dict["results"] as? [[String: Any]] {
                return String(localized: "^[\(results.count) result](inflect: true)")
            }
            return nil
        }
        guard let dict = parsed as? [String: Any] else { return nil }
        switch call.name {
        case "weather":
            let t = dict["temperature_c"] as? Double
            let c = dict["conditions"] as? String ?? ""
            return t.map { String(localized: "\(Int($0))° \(c)") } ?? c
        case "get_location":
            return (dict["location_name"] ?? dict["display"] ?? dict["city"]) as? String
        case "update_memory":
            return (dict["status"] as? String) == "noop" ? String(localized: "No changes") : String(localized: "Updated")
        case "fetch_url":
            return dict["title"] as? String
        case "calendar":
            if let events = dict["events"] as? [[String: Any]], !events.isEmpty {
                return String(localized: "^[\(events.count) event](inflect: true)")
            }
            return dict["mode"] as? String
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
    let toolName: String
    let jsonString: String
    private let parsed: Any?

    init(toolName: String, jsonString: String) {
        self.toolName = toolName
        self.jsonString = jsonString
        if let d = jsonString.data(using: .utf8) {
            self.parsed = try? JSONSerialization.jsonObject(with: d)
        } else {
            self.parsed = nil
        }
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
        if let error = d["error"] as? String, !error.isEmpty {
            ErrorCard(d: d)
        } else {
            switch toolName {
            case "weather":              WeatherCard(d: d)
            case "web_search":           SearchResults(d: d)
            case "get_location":         LocationCard(d: d)
            case "update_memory":         MemoryResult(d: d)
            case "fetch_url":            FetchResult(d: d)
            case "calendar":             CalendarCard(d: d)
            default:                     FieldGrid(dict: d, title: toolName)
            }
        }
    }

    @ViewBuilder
    private func arrayView(items: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                richView(for: item)
                if i < items.count - 1 {
                    ThinDivider().padding(.vertical, 8)
                }
            }
        }
    }
}

// ─── TOOL ICON & COLOR HELPERS ───────────────────────────────────────────

func toolIcon(name: String) -> String {
    switch name {
    case "web_search":              return "magnifyingglass.circle.fill"
    case "fetch_url":               return "doc.text.magnifyingglass"
    case "get_location":            return "location.fill"
    case "weather":                 return "cloud.sun.fill"
    case "update_memory":            return "brain.head.profile"
    case "think":                   return "lightbulb.max.fill"
    case "calendar":                return "calendar"
    default:                        return "wrench.fill"
    }
}

func toolColor(name: String) -> Color {
    switch name {
    case "weather":              return Color(red: 0.20, green: 0.62, blue: 0.95)
    case "web_search":           return Color(red: 0.42, green: 0.48, blue: 0.95)
    case "get_location":         return Color(red: 0.95, green: 0.38, blue: 0.42)
    case "fetch_url":            return Color(red: 0.15, green: 0.65, blue: 0.55)
    case "calendar":             return Color(red: 0.95, green: 0.55, blue: 0.20)
    case "update_memory", "think": return Color(red: 0.62, green: 0.45, blue: 0.90)
    default:                     return Color(red: 0.55, green: 0.58, blue: 0.62)
    }
}

// ─── SHARED RESULT COMPONENTS ────────────────────────────────────────────

func metricPill(icon: String, value: String, color: Color, label: String? = nil) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color)
        Text(value).font(.system(.caption2, design: .rounded).weight(.medium)).foregroundStyle(.primary)
        if let l = label { Text(l).font(.system(size: 9)).foregroundStyle(.tertiary) }
    }
    .lineLimit(1)
    .padding(.horizontal, 8).padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.10)))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.20), lineWidth: 0.5))
}

func headerRow(icon: String, color: Color, title: String, subtitle: String?) -> some View {
    HStack(spacing: 10) {
        ToolBadge(icon: icon, tint: color, size: 26)
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

// ─── VALUE HELPERS ───────────────────────────────────────────────────────

// ─── WEATHER SYMBOL HELPERS ──────────────────────────────────────────────

/// Native SF Symbol for a weather condition (replaces emoji glyphs).
func weatherSymbol(_ c: String, isDay: Bool) -> String {
    let l = c.lowercased()
    if l.contains("thunder")              { return "cloud.bolt.fill" }
    if l.contains("snow")                 { return "cloud.snow.fill" }
    if l.contains("rain") || l.contains("shower") { return "cloud.rain.fill" }
    if l.contains("drizzle")              { return "cloud.drizzle.fill" }
    if l.contains("fog") || l.contains("mist") { return "cloud.fog.fill" }
    if l.contains("cloud") {
        if l.contains("few") || l.contains("part") || l.contains("scattered") || l.contains("mostly sunny") {
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        }
        return "cloud.fill"
    }
    if l.contains("clear") || l.contains("sunny") { return isDay ? "sun.max.fill" : "moon.fill" }
    return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
}

func weatherSymbolColor(_ c: String, isDay: Bool) -> Color {
    let l = c.lowercased()
    if l.contains("thunder")              { return .purple }
    if l.contains("snow")                 { return .cyan }
    if l.contains("rain") || l.contains("shower") || l.contains("drizzle") { return .blue }
    if l.contains("clear") || l.contains("sunny") { return isDay ? .orange : .indigo }
    if l.contains("cloud")                { return .secondary }
    return .secondary
}

func shortTime(_ s: String) -> String {
    let sep: Character = s.contains("T") ? "T" : " "
    guard let t = s.firstIndex(of: sep) else { return s }
    return String(s[s.index(after: t)...].prefix(5))
}

func shortHour(_ s: String) -> String {
    let sep: Character = s.contains("T") ? "T" : " "
    guard let t = s.firstIndex(of: sep) else { return s }
    return String(s[s.index(after: t)...].prefix(2))
}

func shortURL(_ u: String) -> String {
    u.replacingOccurrences(of: "https://", with: "")
     .replacingOccurrences(of: "http://", with: "")
     .replacingOccurrences(of: "www.", with: "")
     .components(separatedBy: "/").first ?? u
}

func formatNumber(_ n: Double) -> String {
    if n == floor(n) && n.isFinite && abs(n) < 1e15 { return String(Int(n)) }
    return String(format: "%.6g", n)
}

func shortDate(_ iso: String) -> String {
    if iso.count >= 10 { return String(iso.suffix(5)) }; return iso
}

func formatEventTime(_ iso: String) -> String {
    if let t = iso.firstIndex(of: "T") {
        let timePart = String(iso[iso.index(after: t)...])
        return String(timePart.prefix(5))
    }
    return iso
}

// MARK: - Container

struct ToolCallsView: View {
    let calls: [ToolCallRecord]; let isStreaming: Bool
    var body: some View { ForEach(calls) { ToolCallBlock(call: $0, isStreaming: isStreaming) } }
}
