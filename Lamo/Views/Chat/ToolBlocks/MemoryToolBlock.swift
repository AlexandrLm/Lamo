import SwiftUI

// MARK: - Memory

struct MemoryResult: View {
    let d: [String: Any]
    private static let handled = Set(["status", "stored", "forgot", "existing_facts", "note"])

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let status = d["status"] as? String ?? ""
            let stored = d["stored"] as? [String] ?? []
            let forgot = d["forgot"] as? [String] ?? []
            let existing = d["existing_facts"] as? [String] ?? []
            let note = d["note"] as? String
            let tint = toolColor(name: "update_memory")

            if status == "noop" {
                HStack(spacing: 10) {
                    ToolBadge(icon: "brain.head.profile", tint: tint, size: 28)
                    Text("No memory changes requested")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 10) {
                    ToolBadge(icon: "brain.head.profile", tint: tint, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status == "saved" ? "Memory updated" : "Memory read")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            if !stored.isEmpty {
                                Chip(text: "+\(stored.count) stored", icon: "plus.circle.fill", tint: .green)
                            }
                            if !forgot.isEmpty {
                                Chip(text: "-\(forgot.count) removed", icon: "minus.circle.fill", tint: .orange)
                            }
                            if let note {
                                Text(note).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                ForEach(stored, id: \.self) { fact in
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 8)).foregroundStyle(.green.opacity(0.5))
                        Text(fact).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.leading, 4)
                }
                ForEach(forgot, id: \.self) { fact in
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle.fill").font(.system(size: 8)).foregroundStyle(.orange.opacity(0.5))
                        Text(fact).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.leading, 4)
                }
                ForEach(existing, id: \.self) { fact in
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
                        Text(fact).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
            }
            FieldGrid(dict: d, handled: Self.handled)
        }
    }
}
