import SwiftUI

// MARK: - Fetch URL

struct FetchResult: View {
    let d: [String: Any]
    private static let handled = Set(["title", "content", "url", "source", "description", "type"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3).foregroundStyle(toolColor(name: "fetch_url").opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    if let t = d["title"] as? String, !t.isEmpty {
                        Text(t)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(shortURL(d["url"] as? String ?? ""))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.blue.opacity(0.6))
                        if let type = d["type"] as? String {
                            Text("· \(type)").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if (d["source"] as? String) == "cache" {
                            Text("· cached").font(.caption2).foregroundStyle(.green.opacity(0.6))
                        }
                    }
                }
            }
            if let desc = d["description"] as? String, !desc.isEmpty {
                Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            if let c = d["content"] as? String, !c.isEmpty {
                Text(String(c.prefix(200)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary.opacity(0.7)).lineLimit(4)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
