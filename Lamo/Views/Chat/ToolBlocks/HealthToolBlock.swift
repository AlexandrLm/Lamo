import SwiftUI

// MARK: - Health

struct HealthCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "mode", "days", "error", "metric", "message",
        "sample_count", "min_bpm", "max_bpm", "avg_bpm", "recent",
        "steps", "hours", "weight_kg", "date", "start", "end",
        "heart_rate", "sleep_hours", "avg_steps", "avg_energy",
    ])

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else if let msg = d["message"] as? String {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.title3).foregroundStyle(toolColor(name: "health").opacity(0.5))
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let mode = d["mode"] as? String ?? ""
                let days = d["days"] as? Int ?? 1
                headerRow(icon: modeIcon(mode), color: toolColor(name: "health"),
                          title: modeLabel(mode),
                          subtitle: days == 1 ? "Today" : "Last \(days) days")

                switch mode {
                case "steps":
                    stepsView
                case "heart_rate":
                    heartRateView
                case "sleep":
                    sleepView
                case "weight":
                    weightView
                case "summary":
                    summaryGrid
                default:
                    genericData
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }

    // MARK: - Mode Helpers

    private func modeIcon(_ mode: String) -> String {
        switch mode {
        case "steps": return "figure.walk"
        case "heart_rate": return "heart.fill"
        case "sleep": return "moon.zzz.fill"
        case "weight": return "scalemass.fill"
        case "summary": return "heart.text.square.fill"
        default: return "heart.fill"
        }
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "heart_rate": return "Heart Rate"
        case "steps": return "Steps"
        case "sleep": return "Sleep"
        case "weight": return "Weight"
        case "summary": return "Health Summary"
        default: return mode.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Heart Rate View

    private var heartRateView: some View {
        let avg = (d["avg_bpm"] as? Int) ?? (d["avg_bpm"] as? Double).map(Int.init) ?? 0
        let minBpm = (d["min_bpm"] as? Int) ?? 0
        let maxBpm = (d["max_bpm"] as? Int) ?? 0
        let samples = d["sample_count"] as? Int ?? 0
        let recent = d["recent"] as? [[String: Any]] ?? []

        return VStack(alignment: .leading, spacing: 10) {
            // Big hero number
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.title).foregroundStyle(.red)
                Text("\(avg)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text("BPM")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Min/max bar
            if minBpm > 0, maxBpm > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("\(minBpm)", systemImage: "arrow.down")
                            .font(.caption2).foregroundStyle(.blue.opacity(0.7))
                        Spacer()
                        Label("\(maxBpm)", systemImage: "arrow.up")
                            .font(.caption2).foregroundStyle(.red.opacity(0.7))
                    }
                    // Range bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06)).frame(height: 6)
                            let range = CGFloat(maxBpm - minBpm)
                            let offset = range > 0 ? CGFloat(avg - minBpm) / range * geo.size.width : geo.size.width / 2
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                                .offset(x: min(geo.size.width - 8, max(0, offset - 4)))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("\(minBpm)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(maxBpm)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
            }

            // Sample count
            if samples > 0 {
                Label("\(samples) readings", systemImage: "chart.dots.scatter")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            // Recent readings
            if !recent.isEmpty {
                Color.white.opacity(0.05).frame(height: 1)
                let bpmValues = recent.compactMap { ($0["bpm"] as? Int).map(Double.init) }
                let times = recent.compactMap { $0["date"] as? String }.map { shortHour($0) }
                SparklineView(values: bpmValues, color: .red, xLabels: times)
                    .frame(height: 70)
            }
        }
    }

    // MARK: - Steps View

    private var stepsView: some View {
        let steps = d["steps"] as? Int ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "figure.walk").font(.title).foregroundStyle(.green)
                Text("\(steps)").font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text("steps").font(.system(.title3, design: .rounded)).foregroundStyle(.secondary)
            }
            // Step goal ring
            let goal = 10000.0
            let pct = min(1.0, Double(steps) / goal)
            HStack(spacing: 8) {
                ProgressView(value: pct).tint(.green)
                Text("\(Int(pct * 100))% of \(Int(goal))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Sleep View

    private var sleepView: some View {
        let hours = d["hours"] as? Double ?? 0
        let start = d["start"] as? String
        let end = d["end"] as? String
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "moon.zzz.fill").font(.title).foregroundStyle(.indigo)
                Text(String(format: "%.1f", hours))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text("hours").font(.system(.title3, design: .rounded)).foregroundStyle(.secondary)
            }
            if let start, let end {
                HStack(spacing: 16) {
                    Label(shortTime(start), systemImage: "bed.double.fill")
                    Label(shortTime(end), systemImage: "alarm.fill")
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Weight View

    private var weightView: some View {
        let kg = d["weight_kg"] as? Double ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "scalemass.fill").font(.title).foregroundStyle(.teal)
            Text(String(format: "%.1f", kg))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
            Text("kg").font(.system(.title3, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        let items: [(String, String, String, Color)] = [
            ("figure.walk", "\(d["steps"] as? Int ?? d["avg_steps"] as? Int ?? 0)", "steps", .green),
            ("heart.fill", "\(d["avg_bpm"] as? Int ?? d["heart_rate"] as? Int ?? 0)", "bpm", .red),
            ("moon.zzz.fill", "\(String(format: "%.1f", d["hours"] as? Double ?? d["sleep_hours"] as? Double ?? 0))", "hrs", .indigo),
            ("scalemass.fill", "\(String(format: "%.1f", d["weight_kg"] as? Double ?? 0))", "kg", .teal),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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

    // MARK: - Generic fallback

    private var genericData: some View {
        ForEach(Array(d.filter { !Self.handled.contains($0.key) && $0.key != "mode" && $0.key != "days" }
            .sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
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
