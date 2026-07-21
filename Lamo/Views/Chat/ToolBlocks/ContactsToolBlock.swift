import SwiftUI

// MARK: - Contacts

struct ContactsCard: View {
    let d: [String: Any]
    private static let handled = Set(["query", "count", "contacts", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let contacts = d["contacts"] as? [[String: Any]] ?? []
                let count = d["count"] as? Int ?? contacts.count
                headerRow(icon: "person.crop.circle.fill", color: toolColor(name: "contacts"),
                          title: "\(count) contact\(count == 1 ? "" : "s")",
                          subtitle: "query: \(d["query"] as? String ?? "")")

                ForEach(Array(contacts.enumerated()), id: \.offset) { i, contact in
                    HStack(alignment: .top, spacing: 8) {
                        // Avatar circle
                        let initials = ((contact["name"] as? String) ?? "?")
                            .split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
                        Text(initials)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(toolColor(name: "contacts").opacity(0.25)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact["name"] as? String ?? "")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary)
                            if let org = contact["organization"] as? String {
                                Text(org).font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let phones = contact["phones"] as? [String] {
                                ForEach(phones, id: \.self) { phone in
                                    Label(phone, systemImage: "phone.fill")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                            if let emails = contact["emails"] as? [String] {
                                ForEach(emails, id: \.self) { email in
                                    Label(email, systemImage: "envelope.fill")
                                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.blue.opacity(0.6))
                                }
                            }
                        }
                    }
                    if i < contacts.count - 1 {
                        Color.white.opacity(0.04).frame(height: 1).padding(.vertical, 2)
                    }
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
