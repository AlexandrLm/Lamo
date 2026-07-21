import SwiftUI

// MARK: - Tool Call Block

struct ToolCallBlock: View {
    let call: ToolCallRecord
    let isStreaming: Bool
    @State private var isExpanded = false
    @State private var cachedSummary: String?
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
        .onAppear { cachedSummary = call.result.flatMap { resultSummary(from: $0) } }
        .onChange(of: call.result) { _, new in cachedSummary = new.flatMap { resultSummary(from: $0) } }
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
                if !isRunning, call.result != nil, !isExpanded {
                    if let summary = cachedSummary {
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
        switch toolName {
        case "weather":              WeatherCard(d: d)
        case "web_search":           SearchResults(d: d)
        case "get_current_time":     TimeCard(d: d)
        case "get_location":         LocationCard(d: d)
        case "get_device_info":      DeviceCard(d: d)
        case "open_url":             OpenURLResult(d: d)
        case "create_reminder":       ReminderResult(d: d)
        case "update_memory":         MemoryResult(d: d)
        case "fetch_url":            FetchResult(d: d)
        case "calendar":             CalendarCard(d: d)
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

func toolIcon(name: String) -> String {
    switch name {
    case "web_search":              return "magnifyingglass.circle.fill"
    case "fetch_url":               return "doc.text.magnifyingglass"
    case "get_current_time":        return "clock.fill"
    case "open_url":                return "safari"
    case "get_location":            return "location.fill"
    case "get_device_info":         return "iphone.gen3"
    case "weather":                 return "cloud.sun.fill"
    case "create_reminder":          return "bell.badge.fill"
    case "update_memory":            return "brain.head.profile"
    case "think":                   return "lightbulb.max.fill"
    case "calendar":                return "calendar"
    default:                        return "wrench.fill"
    }
}

func toolColor(name: String) -> Color {
    switch name {
    case "weather":              return Color(red: 0.30, green: 0.70, blue: 0.95)
    case "web_search":           return Color(red: 0.25, green: 0.60, blue: 0.95)
    case "get_current_time":     return Color(red: 0.50, green: 0.65, blue: 0.85)
    case "get_location":         return Color(red: 0.90, green: 0.35, blue: 0.35)
    case "fetch_url":            return Color(red: 0.25, green: 0.70, blue: 0.60)
    case "calendar":             return Color(red: 0.85, green: 0.40, blue: 0.40)
    default:                     return Color(red: 0.45, green: 0.50, blue: 0.55)
    }
}

// ─── SHARED RESULT COMPONENTS ────────────────────────────────────────────

func metricPill(icon: String, value: String, color: Color, label: String? = nil) -> some View {
    HStack(spacing: 4) {
        Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color.opacity(0.7))
        Text(value).font(.system(.caption2, design: .rounded).weight(.medium)).foregroundStyle(.primary)
        if let l = label { Text(l).font(.system(size: 9)).foregroundStyle(.tertiary) }
    }
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.08)))
}

func headerRow(icon: String, color: Color, title: String, subtitle: String?) -> some View {
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

// MARK: - Sparkline Chart (shared, used by Health)

struct SparklineView: View {
    let values: [Double]
    var color: Color = .red
    var lineWidth: CGFloat = 2
    var showDots: Bool = true
    var xLabels: [String]? = nil

    var body: some View {
        if values.isEmpty {
            Color.clear
        } else {
            HStack(alignment: .top, spacing: 4) {
                yAxis.frame(width: 28)
                chartArea
            }
            if let labels = xLabels, labels.count > 1 {
                xAxis(labels).padding(.leading, 32).padding(.top, 2)
            }
        }
    }

    private var yAxis: some View {
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        return VStack(spacing: 0) {
            Text(fmt(maxV)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            Spacer(minLength: 0)
            Text(fmt(minV)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
        }
    }

    private func xAxis(_ labels: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Text(label).font(.system(size: 7, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                if i < labels.count - 1 { Spacer(minLength: 0) }
            }
        }
    }

    private var chartArea: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = maxV - minV
            let pad = range > 0 ? range * 0.1 : 1
            let low = minV - pad
            let high = maxV + pad
            let span = max(high - low, 1)

            let points: [CGPoint] = values.enumerated().map { i, v in
                let x = values.count > 1 ? w * CGFloat(i) / CGFloat(values.count - 1) : w / 2
                let y = h * (1 - CGFloat((v - low) / span))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // Midline
                Path { path in
                    let mid = h / 2
                    path.move(to: CGPoint(x: 0, y: mid))
                    path.addLine(to: CGPoint(x: w, y: mid))
                }
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(dash: [3, 4]))

                // Gradient fill
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: h))
                    path.addLine(to: first)
                    for p in points.dropFirst() { path.addLine(to: p) }
                    guard let last = points.last else { return }
                    path.addLine(to: CGPoint(x: last.x, y: h))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.2), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))

                // Line
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for p in points.dropFirst() { path.addLine(to: p) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                // Dots
                if showDots && values.count <= 15 {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        Circle().fill(color).frame(width: 4, height: 4).position(p)
                    }
                }
            }
        }
    }

    private func fmt(_ v: Double) -> String {
        if abs(v) >= 1000 { return String(format: "%.0fk", v / 1000) }
        if v == floor(v) { return "\(Int(v))" }
        return String(format: "%.0f", v)
    }
}

// MARK: - Pretty JSON (universal fallback)

struct PrettyJSON: View {
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

struct JSONChip: View {
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

// MARK: - Extra Fields

struct ExtraFields: View {
    let dict: [String: Any]; let handled: Set<String>

    @ViewBuilder
    var body: some View {
        let extra = dict.filter { !handled.contains($0.key) }
        if !extra.isEmpty {
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
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
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

func chipIcon(_ key: String) -> String {
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

func chipValue(_ value: Any) -> String {
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

func chipColor(_ value: Any) -> Color {
    switch value {
    case is String:  return .primary.opacity(0.85)
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
        return n.boolValue ? .green.opacity(0.7) : .orange.opacity(0.7)
    case is NSNumber: return .green.opacity(0.6)
    case is NSNull:   return .secondary
    default:          return .secondary
    }
}

func fmtUptime(_ s: Int) -> String {
    let h = s / 3600, m = (s % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

func weatherEmoji(_ c: String, isDay: Bool) -> String {
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

func parseBytes(_ s: String) -> Int64 {
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
