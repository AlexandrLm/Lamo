import SwiftUI

// MARK: - Time

struct TimeCard: View {
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
