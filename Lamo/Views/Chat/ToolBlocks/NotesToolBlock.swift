import SwiftUI

// MARK: - Notes

struct NotesCard: View {
    let d: [String: Any]
    private static let handled = Set(["mode", "count", "notes", "note", "title", "action", "deleted", "error", "query"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let mode = d["mode"] as? String ?? ""
                switch mode {
                case "list", "search":
                    let notes = d["notes"] as? [[String: Any]] ?? []
                    let count = d["count"] as? Int ?? notes.count
                    headerRow(icon: "note.text", color: toolColor(name: "notes"),
                              title: "\(count) note\(count == 1 ? "" : "s")",
                              subtitle: mode == "search" ? "query: \(d["query"] as? String ?? "")" : nil)
                    ForEach(Array(notes.prefix(10).enumerated()), id: \.offset) { i, note in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text").font(.caption2).foregroundStyle(toolColor(name: "notes").opacity(0.5))
                            Text(note["title"] as? String ?? "")
                                .font(.caption).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            if let date = note["created_at"] as? String {
                                Text(shortDate(date)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                        if i < notes.count - 1 {
                            Color.white.opacity(0.03).frame(height: 1)
                        }
                    }
                case "read":
                    if let note = d["note"] as? [String: Any] {
                        headerRow(icon: "note.text", color: toolColor(name: "notes"),
                                  title: note["title"] as? String ?? "Note",
                                  subtitle: (note["created_at"] as? String).map { "Created \($0)" })
                        if let content = note["content"] as? String {
                            Text(content)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(8)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                        }
                    }
                case "create":
                    let action = d["action"] as? String ?? "saved"
                    let title = d["title"] as? String ?? "Note"
                    HStack(spacing: 8) {
                        Image(systemName: action == "created" ? "plus.circle.fill" : "pencil.circle.fill")
                            .font(.title3).foregroundStyle(toolColor(name: "notes").opacity(0.7))
                        Text("\(action == "created" ? "Created" : "Updated"): \(title)")
                            .font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(.primary)
                    }
                case "delete":
                    HStack(spacing: 8) {
                        Image(systemName: "trash.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                        Text("Deleted: \(d["title"] as? String ?? "note")")
                            .font(.system(.caption, design: .rounded).weight(.medium)).foregroundStyle(.primary)
                    }
                default:
                    PrettyJSON(d: d, title: "notes")
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
