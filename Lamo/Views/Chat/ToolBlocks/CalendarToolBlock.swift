import SwiftUI

// MARK: - Calendar

struct CalendarCard: View {
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
