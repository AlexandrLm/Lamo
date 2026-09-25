import SwiftUI

// MARK: - Calendar

struct CalendarCard: View {
    let d: [String: Any]
    private static let handled = Set(["mode", "events", "event", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(LamoTheme.Colors.error)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else if let events = d["events"] as? [[String: Any]], !events.isEmpty {
                headerRow(icon: "calendar", color: toolColor(name: "calendar"),
                          title: String(localized: "^[\(events.count) event](inflect: true)"),
                          subtitle: d["mode"] as? String)

                ForEach(Array(events.enumerated()), id: \.offset) { i, event in
                    eventRow(event)
                    if i < events.count - 1 {
                        ThinDivider().padding(.vertical, 2)
                    }
                }
            } else if let event = d["event"] as? [String: Any] {
                headerRow(icon: "calendar.badge.plus", color: toolColor(name: "calendar"),
                          title: String(localized: "Event created"), subtitle: d["mode"] as? String)
                eventRow(event)
            } else {
                headerRow(icon: "calendar", color: toolColor(name: "calendar"),
                          title: String(localized: "No events"), subtitle: d["mode"] as? String)
            }
            FieldGrid(dict: d, handled: Self.handled)
        }
    }

    private func eventRow(_ event: [String: Any]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LinearGradient(
                    colors: [toolColor(name: "calendar"), toolColor(name: "calendar").opacity(0.35)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 4)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(event["title"] as? String ?? event["summary"] as? String ?? "")
                    .font(.system(.caption, design: .rounded).weight(.semibold)).foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if let start = event["start"] as? String {
                        Label(formatEventTime(start), systemImage: "clock")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let end = event["end"] as? String {
                        Text("→ \(formatEventTime(end))").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if (event["is_all_day"] as? Bool) == true {
                        Chip(text: String(localized: "ALL DAY"), tint: .teal,
                             font: .system(size: 8, weight: .bold, design: .monospaced))
                    }
                }
                if let cal = event["calendar"] as? String, !cal.isEmpty {
                    Label(cal, systemImage: "calendar")
                        .font(.caption2).foregroundStyle(.tertiary)
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
    }
}
