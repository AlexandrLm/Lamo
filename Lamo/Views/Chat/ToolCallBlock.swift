import SwiftUI

// MARK: - Tool Call Block

struct ToolCallBlock: View {
    let call: ToolCallRecord
    let isStreaming: Bool
    @State private var isExpanded = false

    private var accentColor: Color { Color(red: 0.35, green: 0.55, blue: 0.90) }
    private var isRunning: Bool { call.result == nil && isStreaming }
    private var borderColor: Color { isRunning ? accentColor.opacity(0.35) : Color(white: 0.5).opacity(0.12) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                accentColor.opacity(0.12).frame(height: 1).padding(.vertical, 6)
                if let result = call.result {
                    ToolResultView(toolName: call.name, jsonString: result)
                } else {
                    Text(call.params).font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(isRunning ? 0.2 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1))
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.caption.weight(.medium))
                    .foregroundStyle(isRunning ? accentColor : Color(white: 0.5).opacity(0.45))
                    .symbolEffect(.bounce, value: isRunning)
                Text(name).font(.caption.weight(.medium))
                    .foregroundStyle(isRunning ? Color(.secondaryLabel) : .secondary)
                if isRunning {
                    ProgressView().tint(accentColor).controlSize(.mini)
                    Text("running").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if call.result != nil { Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green.opacity(0.7)) }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var icon: String {
        switch call.name {
        case "web_search": return "globe"
        case "fetch_url": return "doc.text.magnifyingglass"
        case "get_current_time": return "clock"
        case "calculator": return "function"
        case "open_url": return "safari"
        case "wikipedia": return "book.closed"
        case "get_location": return "location.fill"
        case "get_device_info": return "iphone.gen3"
        case "weather": return "cloud.sun.fill"
        case "create_reminder": return "bell.badge.fill"
        case "update_memory": return "brain.fill"
        default: return "wrench.fill"
        }
    }
    private var name: String { call.name.replacingOccurrences(of: "_", with: " ").capitalized }
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
            Text(jsonString).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func richView(for d: [String: Any]) -> some View {
        switch toolName {
        case "weather":         WeatherCard(d: d)
        case "web_search":      SearchResults(d: d)
        case "wikipedia":       WikipediaResult(d: d)
        case "calculator":      CalculatorResult(d: d)
        case "get_current_time": TimeCard(d: d)
        case "get_location":    LocationCard(d: d)
        case "get_device_info": DeviceCard(d: d)
        case "open_url":        OpenURLResult(d: d)
        case "create_reminder": ReminderResult(d: d)
        case "update_memory":   MemoryResult(d: d)
        case "fetch_url":       FetchResult(d: d)
        default:                PrettyJSON(d: d)
        }
    }

    @ViewBuilder
    private func arrayView(items: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                richView(for: item)
                if i < items.count - 1 { Divider().opacity(0.3).padding(.vertical, 4) }
            }
        }
    }
}

// MARK: - Weather Card

private struct WeatherCard: View {
    let d: [String: Any]
    private static let handled = Set(["temperature_c","feels_like_c","humidity_percent","wind_speed_kmh","wind_direction_deg","conditions","is_day","city","sunrise","sunset"])

    var body: some View {
        let temp = d["temperature_c"] as? Double ?? 0
        let feels = d["feels_like_c"] as? Double ?? temp
        let hum = d["humidity_percent"] as? Int ?? 0
        let wind = d["wind_speed_kmh"] as? Double ?? 0
        let cond = d["conditions"] as? String ?? ""
        let isDay = d["is_day"] as? Bool ?? true
        let city = d["city"] as? String ?? ""

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(weatherEmoji(cond, isDay: isDay)).font(.title2)
                Text(city).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Text("\(Int(temp))°C").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(.primary)
            }
            Text(cond).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Label("\(hum)%", systemImage: "humidity.fill")
                Label("\(Int(wind)) km/h", systemImage: "wind")
                Text("Feels \(Int(feels))°").foregroundStyle(.tertiary)
            }.font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
            if let sr = d["sunrise"] as? String, let ss = d["sunset"] as? String {
                HStack(spacing: 16) {
                    Label(shortTime(sr), systemImage: "sunrise.fill")
                    Label(shortTime(ss), systemImage: "sunset.fill")
                }.font(.system(.caption2, design: .rounded)).foregroundStyle(.tertiary)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Search Results

private struct SearchResults: View {
    let d: [String: Any]
    private static let handled = Set(["results","query"])

    var body: some View {
        let results = d["results"] as? [[String: Any]] ?? (d["query"] != nil ? [d] : [])
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 2) {
                    if let t = item["title"] as? String, !t.isEmpty {
                        Text(t).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    }
                    if let s = item["snippet"] as? String, !s.isEmpty {
                        Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let u = item["url"] as? String, !u.isEmpty {
                        Text(shortURL(u)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.blue.opacity(0.7)).lineLimit(1)
                    }
                }.padding(.vertical, 4)
                if i < results.count - 1 { Divider().opacity(0.3) }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Wikipedia

private struct WikipediaResult: View {
    let d: [String: Any]
    private static let handled = Set(["error","extract","title","page_id","url","results","query"])
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = d["error"] as? String { Text(error).font(.caption2).foregroundStyle(.secondary) }
            else if let extract = d["extract"] as? String {
                if let t = d["title"] as? String { Text(t).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(.primary) }
                Text(extract).font(.caption2).foregroundStyle(.secondary).lineLimit(5)
            } else { SearchResults(d: d) }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Calculator

private struct CalculatorResult: View {
    let d: [String: Any]
    private static let handled = Set(["expression","error","result"])
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let expr = d["expression"] as? String ?? ""
            if let error = d["error"] as? String {
                HStack { Text(expr).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary); Text("= ❌ \(error)").font(.caption).foregroundStyle(.orange) }
            } else {
                let r = d["result"] as? Double ?? 0
                HStack(spacing: 6) {
                    Text(expr).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.secondary)
                    Text("=").font(.subheadline).foregroundStyle(.tertiary)
                    Text(formatNumber(r)).font(.system(.subheadline, design: .monospaced).weight(.bold)).foregroundStyle(.primary)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Time

private struct TimeCard: View {
    let d: [String: Any]
    private static let handled = Set(["time","iso_date","weekday","timezone","utc_offset_hours","unix_timestamp"])
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let time = d["time"] as? String ?? ""
            let wd = d["weekday"] as? String ?? ""
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(time).font(.system(.title3, design: .monospaced).weight(.bold)).foregroundStyle(.primary)
                Text(wd).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            }
            Text("\(d["iso_date"] as? String ?? "") · \(d["timezone"] as? String ?? "")").font(.caption2).foregroundStyle(.tertiary)
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Location

private struct LocationCard: View {
    let d: [String: Any]
    private static let handled = Set(["location_name","display","city","region","country","latitude","longitude","altitude_m","horizontal_accuracy_m","source","timezone"])
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let name = d["location_name"] as? String ?? d["display"] as? String ?? d["city"] as? String ?? ""
            HStack(spacing: 6) { Image(systemName: "mappin.and.ellipse").font(.caption).foregroundStyle(.red); Text(name).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(.primary) }
            Text("\(String(format: "%.4f", d["latitude"] as? Double ?? 0)), \(String(format: "%.4f", d["longitude"] as? Double ?? 0))").font(.caption2).foregroundStyle(.tertiary)
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Device Info

private struct DeviceCard: View {
    let d: [String: Any]
    private static let handled = Set(["device_name","device_model","system_name","system_version","battery_level","battery_state","physical_memory_gb","free_storage","total_storage","processor_count","uptime_seconds","is_low_power_mode"])
    var body: some View {
        let name = d["device_name"] as? String ?? ""; let model = d["device_model"] as? String ?? ""
        let os = "\(d["system_name"] as? String ?? "") \(d["system_version"] as? String ?? "")"
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(name).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(.primary); Spacer(); Text(model).font(.caption2).foregroundStyle(.tertiary) }
            Text(os).font(.caption2).foregroundStyle(.secondary)
            BatteryBar(level: d["battery_level"] as? Int ?? 0)
            StorageBar(free: d["free_storage"] as? String ?? "", total: d["total_storage"] as? String ?? "")
            Text("\(d["physical_memory_gb"] as? String ?? "") GB RAM · Uptime \(fmtUptime(d["uptime_seconds"] as? Int ?? 0))").font(.caption2).foregroundStyle(.tertiary)
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

private struct BatteryBar: View {
    let level: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: level <= 10 ? "battery.0percent" : level <= 25 ? "battery.25percent" : "battery.75percent")
                .font(.caption2).foregroundStyle(level <= 10 ? .red : level <= 20 ? .orange : .green)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.1)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(level <= 10 ? Color.red : level <= 20 ? Color.orange : Color.green)
                        .frame(width: geo.size.width * CGFloat(level) / 100, height: 4)
                }
            }.frame(height: 4)
            Text("\(level)%").font(.caption2).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
        }
    }
}
private struct StorageBar: View {
    let free: String; let total: String
    var body: some View {
        let fb = parseBytes(free); let tb = parseBytes(total)
        if tb > 0 {
            let frac = CGFloat(tb - fb) / CGFloat(tb)
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").font(.caption2).foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.1)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(frac > 0.9 ? Color.orange : Color.white.opacity(0.3))
                            .frame(width: geo.size.width * frac, height: 4)
                    }
                }.frame(height: 4)
                Text("\(free) free").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Open URL

private struct OpenURLResult: View {
    let d: [String: Any]
    private static let handled = Set(["opened","url"])
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let opened = d["opened"] as? Bool ?? false
            HStack(spacing: 4) {
                Image(systemName: opened ? "safari" : "xmark.circle").font(.caption).foregroundStyle(opened ? .blue : .red)
                Text(opened ? "Opened in Safari" : "Could not open").font(.caption).foregroundStyle(.secondary)
                Text(shortURL(d["url"] as? String ?? "")).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Reminder

private struct ReminderResult: View {
    let d: [String: Any]
    private static let handled = Set(["error","status","title","due_date","reminder_id","notes"])
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = d["error"] as? String { Label(error, systemImage: "xmark.circle").font(.caption).foregroundStyle(.orange) }
            else { HStack(spacing: 4) { Image(systemName: "bell.badge.fill").font(.caption).foregroundStyle(.yellow); Text(d["title"] as? String ?? "").font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(.primary); Spacer(); Image(systemName: "checkmark").font(.caption2).foregroundStyle(.green) } }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Memory

private struct MemoryResult: View {
    let d: [String: Any]
    private static let handled = Set(["status","info"])
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if (d["status"] as? String) == "noop" { Text("No new facts").font(.caption2).foregroundStyle(.tertiary) }
            else { Label("Updated", systemImage: "brain.fill").font(.caption).foregroundStyle(.purple.opacity(0.8)) }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Fetch URL

private struct FetchResult: View {
    let d: [String: Any]
    private static let handled = Set(["title","content","url","source","description","type"])
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let t = d["title"] as? String, !t.isEmpty { Text(t).font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(.primary).lineLimit(1) }
            if let c = d["content"] as? String, !c.isEmpty { Text(String(c.prefix(200))).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
            HStack {
                Text(shortURL(d["url"] as? String ?? "")).font(.system(.caption2, design: .monospaced)).foregroundStyle(.blue.opacity(0.7))
                if (d["source"] as? String) == "cache" { Text("· cached").font(.caption2).foregroundStyle(.tertiary) }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Extra Fields (unhandled keys footer)

private struct ExtraFields: View {
    let dict: [String: Any]; let handled: Set<String>
    var body: some View {
        let extra = dict.filter { !handled.contains($0.key) }
        if extra.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Color.white.opacity(0.06).frame(height: 1).padding(.vertical, 2)
                FlowLayout(spacing: 4) {
                    ForEach(extra.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 3) {
                            Text(key.replacingOccurrences(of: "_", with: " ")).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
                            Text(":").font(.system(size: 8)).foregroundStyle(.tertiary)
                            Text(chipValue(value)).font(.system(size: 9, design: .monospaced)).foregroundStyle(chipColor(value))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        )
    }
}

// MARK: - Pretty JSON (universal fallback)

private struct PrettyJSON: View {
    let d: [String: Any]
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 4) {
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
        HStack(spacing: 3) {
            Image(systemName: chipIcon(key)).font(.system(size: 8)).foregroundStyle(.tertiary)
            Text(key.replacingOccurrences(of: "_", with: " ")).font(.system(size: 9, design: .monospaced)).foregroundStyle(.blue.opacity(0.5))
            Text(chipValue(value)).font(.system(size: 9, design: .monospaced).weight(.medium)).foregroundStyle(chipColor(value)).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Helpers

private func chipIcon(_ key: String) -> String {
    switch key {
    case let k where k.contains("temp"): return "thermometer.medium"
    case let k where k.contains("humid"): return "humidity.fill"
    case let k where k.contains("wind"): return "wind"
    case let k where k.contains("url"): return "link"
    case let k where k.contains("city") || k.contains("location"): return "mappin.and.ellipse"
    case let k where k.contains("time") || k.contains("date"): return "clock"
    case let k where k.contains("battery"): return "battery.75percent"
    case let k where k.contains("storage") || k.contains("disk"): return "internaldrive"
    case let k where k.contains("memory") || k.contains("ram"): return "memorychip"
    case let k where k.contains("status"): return "circlebadge"
    case let k where k.contains("error"): return "xmark.circle"
    case let k where k.contains("name") || k.contains("title"): return "textformat"
    case let k where k.contains("id"): return "number"
    case let k where k.contains("count") || k.contains("number"): return "number.circle"
    default: return "circle.fill"
    }
}

private func chipValue(_ value: Any) -> String {
    switch value {
    case let s as String where s.count > 60: return "\"\(s.prefix(60))…\""
    case let s as String: return s
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): return n.boolValue ? "true" : "false"
    case let n as NSNumber: return formatNumber(n.doubleValue)
    case is NSNull: return "—"
    case let arr as [Any]: return "[\(arr.count)]"
    case let d as [String: Any]: return "{\(d.count)}"
    default: return "\(value)"
    }
}

private func chipColor(_ value: Any) -> Color {
    switch value {
    case is String: return .primary.opacity(0.9)
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): return n.boolValue ? .green.opacity(0.7) : .orange.opacity(0.7)
    case is NSNumber: return .green.opacity(0.7)
    case is NSNull: return .secondary
    default: return .secondary
    }
}

// MARK: - Flow Layout (wraps chips)

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

// MARK: - Shared

private func fmtUptime(_ s: Int) -> String { let h=s/3600,m=(s%3600)/60; return h>0 ? "\(h)h \(m)m" : "\(m)m" }
private func weatherEmoji(_ c: String, isDay: Bool) -> String {
    let l = c.lowercased()
    if l.contains("clear") { return isDay ? "☀️" : "🌙" }
    if l.contains("cloud") { return isDay ? "⛅" : "☁️" }
    if l.contains("fog") { return "🌫️" }
    if l.contains("drizzle") { return "🌦️" }
    if l.contains("rain") || l.contains("shower") { return "🌧️" }
    if l.contains("snow") { return "🌨️" }
    if l.contains("thunder") { return "⛈️" }
    return "🌡️"
}
private func shortTime(_ iso: String) -> String {
    if let t = iso.firstIndex(of: "T") { return String(String(iso[iso.index(after: t)...]).prefix(5)) }; return iso
}
private func shortURL(_ u: String) -> String {
    u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        .replacingOccurrences(of: "www.", with: "").components(separatedBy: "/").first ?? u
}
private func formatNumber(_ n: Double) -> String {
    if n == floor(n) && n.isFinite && abs(n) < 1e15 { return String(Int(n)) }
    return String(format: "%.6g", n)
}
private func parseBytes(_ s: String) -> Int64 {
    let c = s.lowercased().replacingOccurrences(of: ",", with: "")
    if c.hasSuffix("gb") { return Int64((Double(c.replacingOccurrences(of: "gb", with: "").trimmingCharacters(in: .whitespaces)) ?? 0) * 1_073_741_824) }
    if c.hasSuffix("mb") { return Int64((Double(c.replacingOccurrences(of: "mb", with: "").trimmingCharacters(in: .whitespaces)) ?? 0) * 1_048_576) }
    return Int64(c) ?? 0
}

// MARK: - Container

struct ToolCallsView: View {
    let calls: [ToolCallRecord]; let isStreaming: Bool
    var body: some View { ForEach(calls) { ToolCallBlock(call: $0, isStreaming: isStreaming) } }
}
