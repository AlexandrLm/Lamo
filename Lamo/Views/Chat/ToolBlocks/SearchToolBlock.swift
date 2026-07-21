import SwiftUI
import UIKit

// MARK: - Search Results

/// Renders search results. Tapping a result fetches and displays the page content inline.
struct SearchResults: View {
    let d: [String: Any]
    private static let handled = Set(["results", "query"])

    var body: some View {
        if let results = d["results"] as? [[String: Any]] {
            let query = d["query"] as? String ?? ""
            VStack(alignment: .leading, spacing: 0) {
                if !query.isEmpty {
                    queryHeader(query, count: results.count)
                }
                ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                    SearchResultCard(item: item)
                }
            }
        } else {
            SearchResultCard(item: d)
        }
    }

    private func queryHeader(_ query: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(toolColor(name: "web_search"))
            Text(query)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Text("\(count) results")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(toolColor(name: "web_search").opacity(0.06))
        )
        .padding(.bottom, 12)
    }
}

// MARK: - Single Card

private struct SearchResultCard: View {
    let item: [String: Any]

    private var title: String { item["title"] as? String ?? "" }
    private var snippet: String { item["snippet"] as? String ?? "" }
    private var url: String { item["url"] as? String ?? "" }
    private var initialContent: String { item["content"] as? String ?? "" }
    private var domain: String { extractDomain(url) }

    @State private var isExpanded = false
    @State private var fetchedContent: String?
    @State private var isFetching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                } else {
                    if !initialContent.isEmpty {
                        fetchedContent = initialContent
                    } else {
                        fetchContent()
                    }
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    // Domain avatar
                    ZStack {
                        Circle()
                            .fill(domainColor(domain).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text(String(domain.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(domainColor(domain))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if !title.isEmpty {
                            Text(title)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }

                        if !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(.caption2, design: .serif))
                                .foregroundStyle(.secondary)
                                .lineLimit(isExpanded ? nil : 3)
                        }

                        if !url.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 7))
                                Text(shortURL(url))
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundStyle(.blue.opacity(0.5))
                            .lineLimit(1)
                            .padding(.top, 2)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.15))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.top, 4)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
            .padding(.vertical, 10)

            // ── Expanded content ──
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Color.white.opacity(0.06).frame(height: 1)

                    if isFetching {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.secondary)
                            Text("Fetching page content...")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                    } else if let content = fetchedContent, !content.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 8))
                                Text("PAGE CONTENT")
                                    .font(.system(size: 8, design: .monospaced))
                            }
                            .foregroundStyle(.tertiary.opacity(0.5))

                            ScrollView(.vertical) {
                                Text(formattedContent(content))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.8))
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                                    )
                            )
                        }
                    } else {
                        Text("Could not fetch content from this page.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    }

                    // Open in browser button
                    if let pageURL = URL(string: url) {
                        Button {
                            UIApplication.shared.open(pageURL)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                    .font(.system(size: 10))
                                Text("Open in browser")
                                    .font(.system(size: 10, design: .monospaced))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8))
                            }
                            .foregroundStyle(.blue.opacity(0.6))
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 10)
            }

            Color.white.opacity(0.04).frame(height: 1)
        }
    }

    private func fetchContent() {
        guard let pageURL = URL(string: url), !isFetching else { return }
        isFetching = true
        Task {
            let content = try? await WebFetcher.fetch(url: pageURL)
            await MainActor.run {
                self.fetchedContent = content.map { String($0.prefix(3000)) }
                self.isFetching = false
            }
        }
    }

    private func formattedContent(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 || $0.isEmpty }
        var result = cleaned.joined(separator: "\n")
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractDomain(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return "?" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private func domainColor(_ domain: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.25, green: 0.60, blue: 0.95),
            Color(red: 0.90, green: 0.35, blue: 0.35),
            Color(red: 0.30, green: 0.70, blue: 0.50),
            Color(red: 0.85, green: 0.55, blue: 0.20),
            Color(red: 0.55, green: 0.40, blue: 0.90),
            Color(red: 0.90, green: 0.30, blue: 0.60),
            Color(red: 0.20, green: 0.70, blue: 0.70),
            Color(red: 0.70, green: 0.50, blue: 0.30),
        ]
        var hash = 0
        for byte in domain.utf8 { hash = hash &* 31 &+ Int(byte) }
        return palette[abs(hash) % palette.count]
    }
}
