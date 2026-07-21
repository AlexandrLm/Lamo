import SwiftUI

// MARK: - Shortcuts

struct ShortcutResult: View {
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
