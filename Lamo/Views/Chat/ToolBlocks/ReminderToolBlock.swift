import SwiftUI

// MARK: - Reminder

struct ReminderResult: View {
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
