import SwiftUI

// MARK: - Calendar Availability

struct CalendarAvailabilityCard: View {
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
