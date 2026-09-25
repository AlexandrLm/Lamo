import SwiftUI

// MARK: - Fetch URL Result

struct FetchResult: View {
    let d: [String: Any]
    private static let handled = Set(["title", "content", "url", "source", "description", "type"])

    private var title: String { d["title"] as? String ?? "" }
    private var content: String { d["content"] as? String ?? "" }
    private var url: String { d["url"] as? String ?? "" }
    private var desc: String { d["description"] as? String ?? "" }
    private var type: String { d["type"] as? String ?? "" }
    private var source: String { d["source"] as? String ?? "" }
    private var domain: String {
        guard let u = URL(string: url), let host = u.host else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var accentColor: Color { toolColor(name: "fetch_url") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──
            HStack(alignment: .top, spacing: 12) {
                ToolBadge(icon: "doc.text.fill", tint: accentColor, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    if !domain.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 8))
                            Text(domain)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                    }
                }

                Spacer()

                // Status chips
                VStack(alignment: .trailing, spacing: 4) {
                    if source == "cache" {
                        Chip(text: String(localized: "cached"), icon: "clock.arrow.circlepath", tint: .orange)
                    }
                    if !type.isEmpty {
                        Chip(text: type, tint: .secondary)
                    }
                }
            }
            .padding(.bottom, 10)

            // ── Description ──
            if !desc.isEmpty {
                Text(desc)
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.bottom, 8)
            }

            // ── Content preview ──
            if !content.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 8))
                        Text("PAGE CONTENT")
                            .font(.system(size: 8, design: .monospaced))
                    }
                    .foregroundStyle(.tertiary.opacity(0.5))
                    .padding(.bottom, 2)

                    Text(formattedContent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(6)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LamoTheme.Colors.fillSubtle)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(LamoTheme.Colors.fillStrong.opacity(0.6), lineWidth: 0.5)
                                )
                        )
                }
            }

            FieldGrid(dict: d, handled: Self.handled)
        }
        .padding(.horizontal, 2)
    }

    private var formattedContent: String {
        // Clean up: remove excessive whitespace, collapse blank lines
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 || $0.isEmpty }
        var result = cleaned.joined(separator: "\n")
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
