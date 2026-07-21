import Foundation
import LiteRTLM

// MARK: - Web Search Tool

struct WebSearchTool: Tool {
    static let name = "web_search"
    static let description = "Search the internet. Returns titles, snippets, and URLs."

    @ToolParam(description: "Search query string.")
    var query: String

    @ToolParam(description: "Max results to return.")
    var maxResults: Int = 5

    @ToolParam(description: "Time filter: day, week, month, year.")
    var timeRange: String?

    func run() async throws -> Any {
        var paramsDesc = "{\"query\": \"\(query)\", \"maxResults\": \(maxResults)"
        if let tr = timeRange { paramsDesc += ", \"timeRange\": \"\(tr)\"" }
        paramsDesc += "}"
        await ToolCallReporter.shared.reportCall(name: Self.name, params: paramsDesc)

        var searchResults = try await SearchProvider.shared.search(query: query, maxResults: maxResults)

        // Post-filter by timeRange if specified (SearXNG doesn't support it natively in basic mode)
        if let tr = timeRange?.lowercased() {
            let cutoff: TimeInterval
            switch tr {
            case "day": cutoff = 86400
            case "week": cutoff = 604800
            case "month": cutoff = 2592000
            case "year": cutoff = 31536000
            default: cutoff = 0
            }
            if cutoff > 0 {
                // Append time range to query for providers that support it
                searchResults = try await SearchProvider.shared.search(
                    query: "\(query) after:\(formatTimeConstraint(tr))",
                    maxResults: maxResults
                )
            }
        }

        let shouldFetch = AppDefaults.webAutoFetch.wrappedValue
        let result: Any
        if shouldFetch && !searchResults.isEmpty {
            // Smart fetch: only fetch pages with thin snippets (<100 chars).
            // Results with substantial snippets are already useful to the model.
            let toFetch = searchResults.enumerated().filter { i, sr in
                let snippet = sr["snippet"] ?? ""
                return snippet.count < 100 && i < 3
            }

            if !toFetch.isEmpty {
                let fetchedContents = await withTaskGroup(of: (Int, String).self) { group in
                    for (i, sr) in toFetch {
                        guard let urlStr = sr["url"], let url = URL(string: urlStr) else { continue }
                        group.addTask {
                            if let content = try? await WebFetcher.fetch(url: url) {
                                return (i, String(content.prefix(1500)))
                            }
                            return (i, "")
                        }
                    }
                    var results: [(Int, String)] = []
                    for await r in group { if !r.1.isEmpty { results.append(r) } }
                    return results
                }

                var enrichedResults: [[String: Any]] = []
                for (i, sr) in searchResults.enumerated() {
                    var enriched: [String: Any] = ["title": sr["title"] ?? "", "snippet": sr["snippet"] ?? "", "url": sr["url"] ?? ""]
                    if let entry = fetchedContents.first(where: { $0.0 == i }) {
                        enriched["content"] = entry.1
                    }
                    enrichedResults.append(enriched)
                }
                result = enrichedResults
            } else {
                result = searchResults
            }
        } else {
            result = searchResults
        }

        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }

    /// Maps time range to a search-engine-friendly time constraint string.
    private func formatTimeConstraint(_ range: String) -> String {
        switch range {
        case "day": return "today"
        case "week": return "this week"
        case "month": return "this month"
        case "year": return "this year"
        default: return ""
        }
    }
}

// MARK: - Fetch URL Tool

struct FetchUrlTool: Tool {
    static let name = "fetch_url"
    static let description = "Fetch and extract content from a URL."

    @ToolParam(description: "URL to fetch content from.")
    var url: String

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(name: Self.name, params: "{\"url\": \"\(url)\"}")

        guard let fetchURL = URL(string: url) else {
            let err: [String: Any] = ["error": "Invalid URL"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            throw FetchError.invalidURL
        }

        if let cached = URLCacheStore.shared.content(for: url) {
            let cachedResult: [String: Any] = ["content": cached, "url": url, "source": "cache"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: cachedResult)
            return cachedResult
        }

        let result = try await WebFetcher.fetchStructured(url: fetchURL)
        var output: [String: Any] = [:]
        if let title = result.title, !title.isEmpty { output["title"] = title }
        if let description = result.description, !description.isEmpty { output["description"] = description }
        if let contentType = result.contentType { output["type"] = contentType }
        output["content"] = result.content
        output["url"] = url

        if !result.content.isEmpty { URLCacheStore.shared.setContent(result.content, for: url) }

        await ToolCallReporter.shared.reportResult(name: Self.name, result: output)
        return output
    }
}

