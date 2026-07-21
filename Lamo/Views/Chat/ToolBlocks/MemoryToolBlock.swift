import SwiftUI

// MARK: - Memory

struct MemoryResult: View {
    let d: [String: Any]
    private static let handled = Set(["status", "info", "existing_facts", "stored_facts", "deleted_facts"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let status = d["status"] as? String ?? ""
            let stored = d["stored_facts"] as? [String] ?? []
            let deleted = d["deleted_facts"] as? [String] ?? []
            let existing = d["existing_facts"] as? [String] ?? []

            if status == "noop" {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3).foregroundStyle(.purple.opacity(0.4))
                    Text("No new facts to store")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3).foregroundStyle(.purple.opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memory updated").font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                        if !stored.isEmpty {
                            Text("+\(stored.count) stored").font(.caption2).foregroundStyle(.green.opacity(0.7))
                        }
                        if !deleted.isEmpty {
                            Text("-\(deleted.count) removed").font(.caption2).foregroundStyle(.orange.opacity(0.7))
                        }
                    }
                }
                // Show facts
                ForEach(stored, id: \.self) { fact in
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 8)).foregroundStyle(.green.opacity(0.5))
                        Text(fact).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.leading, 4)
                }
                ForEach(existing.prefix(3), id: \.self) { fact in
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
                        Text(fact).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
