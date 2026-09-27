import Foundation
import LiteRTLM

// MARK: - Web Search Tool

struct WebSearchTool: Tool {
    static let name = ToolDefinitions.WebSearch.name
    static let description = ToolDefinitions.WebSearch.description

    @ToolParam(description: "Short keyword query (2-6 words works best), NOT a full sentence. Write it in the user's language.")
    var query: String

    @ToolParam(description: "Number of results, 1-5. The default 5 is enough for most questions — prefer 3 to save context.")
    var maxResults: Int = 5

    @ToolParam(description: "Freshness filter: 'day', 'week', 'month', or 'year'. Set only when the user asks about recent events.")
    var timeRange: String?

    private static let validTimeRanges: Set<String> = ["day", "week", "month", "year"]

    func run() async throws -> Any {
        // Cap at 5: each result costs ~100-400 tokens, so 10 results alone can
        // eat a small on-device context window before the answer even starts.
        let clampedMax = max(1, min(maxResults, 5))
        let cleanQuery = SearchResultCompactor.sanitizeQuery(query)
        guard !cleanQuery.isEmpty else {
            let err: [String: Any] = [
                "error": String(localized: "Empty search query"),
                "hint": "Provide 2-6 keywords to search for, then retry.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }
        let normalizedRange = timeRange?.lowercased()
        let range = normalizedRange.flatMap { Self.validTimeRanges.contains($0) ? $0 : nil }

        var params: [String: Any] = ["query": cleanQuery, "maxResults": clampedMax]
        if let range { params["timeRange"] = range }
        await ToolCallReporter.shared.reportCall(name: Self.name, params: ToolReportHelper.paramsJSONString(params))

        if let notice = await AgenticLoopBudget.shared.softStopNotice() {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: notice)
            return notice
        }

        let result: Any
        do {
            let searchResults = try await SearchProvider.shared.search(
                query: cleanQuery, maxResults: clampedMax, timeRange: range
            )
            var enriched = await enrichWithFetchedContent(searchResults)
            // Domain-aware fit BEFORE the generic truncation: keeps every URL and
            // title intact, shrinks excerpts/snippets first. The generic pass in
            // limitResult() stays as a final safety net.
            let budget = await AgenticLoopBudget.shared.projectedResultLimit()
            enriched = SearchResultCompactor.fitResults(enriched, tokenLimit: budget)
            result = enriched
        } catch {
            let err: [String: Any] = [
                "error": String(localized: "Web search failed: \(error.localizedDescription)"),
                "hint": "Rephrase the query and retry once. If it keeps failing, the internet may be unreachable — say so and answer from your own knowledge, noting it may be outdated.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }

        let limited = await AgenticLoopBudget.shared.limitResult(result)
        await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
        return limited
    }

    /// Smart fetch: pull a short excerpt only for results with thin snippets
    /// (<80 chars), max 2 pages. Skipped entirely when the token budget is tight —
    /// fetching would burn network and tokens for data that gets truncated anyway.
    /// The model can always call fetch_url for the full page afterwards.
    private func enrichWithFetchedContent(_ searchResults: [[String: String]]) async -> [[String: Any]] {
        let base: [[String: Any]] = searchResults.map {
            ["title": $0["title"] ?? "", "snippet": $0["snippet"] ?? "", "url": $0["url"] ?? ""]
        }
        guard AppDefaults.webAutoFetch.wrappedValue, !searchResults.isEmpty else { return base }

        let projectedLimit = await AgenticLoopBudget.shared.projectedResultLimit()
        guard projectedLimit >= 600 else { return base }

        let toFetch = searchResults.enumerated().filter { i, sr in
            let snippet = sr["snippet"] ?? ""
            return snippet.count < 80 && i < 2
        }
        guard !toFetch.isEmpty else { return base }

        let fetchedContents = await withTaskGroup(of: (Int, String).self) { group in
            for (i, sr) in toFetch {
                guard let urlStr = sr["url"], let url = URL(string: urlStr) else { continue }
                group.addTask {
                    if let content = try? await WebFetcher.fetch(url: url) {
                        return (i, SearchResultCompactor.cutAtBoundary(content, maxChars: 900))
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
        return enrichedResults
    }
}

// MARK: - Fetch URL Tool

struct FetchUrlTool: Tool {
    static let name = ToolDefinitions.FetchURL.name
    static let description = ToolDefinitions.FetchURL.description

    @ToolParam(description: "Full URL starting with http:// or https:// — copy it exactly from a search result or the user's message.")
    var url: String

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(name: Self.name, params: ToolReportHelper.paramsJSONString(["url": url]))
        if let notice = await AgenticLoopBudget.shared.softStopNotice() {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: notice)
            return notice
        }

        guard let fetchURL = URL(string: url), let scheme = fetchURL.scheme, scheme.hasPrefix("http") else {
            let err: [String: Any] = [
                "error": String(localized: "Invalid URL: '\(url)'"),
                "hint": "The URL is malformed. Copy the exact URL (including https://) from the search results or the user's message and retry once.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }

        // Single cache: WebFetcher's internal NSCache (TTL + in-flight dedup).
        // URLCacheStore is intentionally not used here to avoid double caching.
        do {
            let result = try await WebFetcher.fetchStructured(url: fetchURL)
            var output: [String: Any] = [:]
            if let title = result.title, !title.isEmpty { output["title"] = title }
            if let description = result.description, !description.isEmpty { output["description"] = description }
            if let contentType = result.contentType { output["type"] = contentType }
            output["content"] = await budgetedContent(result.content)
            output["url"] = url

            let limited = await AgenticLoopBudget.shared.limitResult(output)
            await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
            return limited
        } catch {
            let err: [String: Any] = [
                "error": String(localized: "Failed to fetch the page: \(error.localizedDescription)"),
                "hint": "The page could not be loaded (site down, blocked, or no internet). Try a different URL from the search results instead.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }
    }

    /// Trim page text to the current token budget at a sentence boundary, keeping
    /// the head of the page (usually the lede with the answer). The generic
    /// truncation in `limitResult()` stays as a final safety net.
    private func budgetedContent(_ content: String) async -> String {
        let limit = await AgenticLoopBudget.shared.projectedResultLimit()
        var target = min(content.count, max(400, limit * 3))
        var text = SearchResultCompactor.cutAtBoundary(content, maxChars: target)
        // Non-ASCII text packs ~1 token/char, so a char-based first guess can still
        // overshoot — halve until the real estimate fits (never below 400 chars,
        // shorter than that is rarely useful anyway).
        var rounds = 0
        while SearchResultCompactor.estimateTokens(of: text) > limit, target > 400, rounds < 6 {
            rounds += 1
            target = max(400, target / 2)
            text = SearchResultCompactor.cutAtBoundary(content, maxChars: target)
        }
        return text
    }
}
