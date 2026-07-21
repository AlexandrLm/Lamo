import SwiftUI

// MARK: - Search

struct SearchResults: View {
    let d: [String: Any]
    private static let handled = Set(["results", "query"])

    var body: some View {
        let results = d["results"] as? [[String: Any]]
            ?? (d["query"] != nil ? [d] : [])
        let query = d["query"] as? String ?? ""

        VStack(alignment: .leading, spacing: 0) {
            if !query.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                    Text(query).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text("· \(results.count)").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 6)
            }

            ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 8) {
                    // Number badge
                    Text("\(i + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(Color.white.opacity(0.06))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        if let t = item["title"] as? String, !t.isEmpty {
                            Text(t)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary).lineLimit(2)
                        }
                        if let s = item["snippet"] as? String, !s.isEmpty {
                            Text(s)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        }
                        if let c = item["content"] as? String, !c.isEmpty {
                            Text(String(c.prefix(160)))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary.opacity(0.7)).lineLimit(2)
                        }
                        if let u = item["url"] as? String, !u.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "link").font(.system(size: 8))
                                Text(shortURL(u))
                                    .font(.system(.caption2, design: .monospaced))
                            }
                            .foregroundStyle(.blue.opacity(0.6))
                            .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 6)
                if i < results.count - 1 {
                    Color.white.opacity(0.04).frame(height: 1)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

// MARK: - Wikipedia

struct WikipediaResult: View {
    let d: [String: Any]
    private static let handled = Set(["error", "extract", "title", "page_id", "url", "results", "query"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else if let extract = d["extract"] as? String {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages.fill")
                        .font(.title3).foregroundStyle(.white.opacity(0.3))
                    VStack(alignment: .leading, spacing: 4) {
                        if let t = d["title"] as? String {
                            Text(t)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        Text(extract)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(6)
                        if let url = d["url"] as? String {
                            Text(shortURL(url))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.blue.opacity(0.6))
                        }
                    }
                }
            } else {
                SearchResults(d: d)
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
