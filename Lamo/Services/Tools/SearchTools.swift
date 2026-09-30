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
            let budget = await AgenticLoopBudget.shared.projectedResultLimit()
            enriched = SearchResultCompactor.fitResults(enriched, tokenLimit: budget)
            result = enriched
        } catch {
            let err: [String: Any] = [
                "error": String(localized: "Web search failed: \(error.localizedDescription)"),
                "hint": "Rephrase the query and retry once. If it keeps failing, say the internet is unreachable and do not invent facts.",
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
            return err
        }

        let limited = await AgenticLoopBudget.shared.limitResult(result)
        await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
        return limited
    }

    /// Smart fetch: pull a short excerpt only for results with thin snippets
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
                        let excerpt = SearchResultCompactor.cutAtBoundary(content, maxChars: 900)
                        return (i, FetchUrlTool.wrapUntrusted(excerpt))
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

    @ToolParam(description: "Full secure URL starting with https:// — copy it exactly from a search result or the user's message.")
    var url: String

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(name: Self.name, params: ToolReportHelper.paramsJSONString(["url": url]))
        if let notice = await AgenticLoopBudget.shared.softStopNotice() {
            await ToolCallReporter.shared.reportResult(name: Self.name, result: notice)
            return notice
        }

        guard let fetchURL = URL(string: url) else {
            return await reject("Invalid URL: '\(url)'", hint: "The URL is malformed. Copy the exact URL (including https://) from the search results or the user's message and retry once.")
        }
        do {
            try SecureURLPolicy.validate(fetchURL)
            try await SecureURLPolicy.validateResolvedAddresses(of: fetchURL)
        } catch {
            return await reject(
                "Blocked URL: '\(url)'",
                hint: "Only public https:// pages can be fetched. Use a link from the search results instead."
            )
        }

        do {
            let result = try await WebFetcher.fetchStructured(url: fetchURL)
            if let finalURL = result.finalURL {
                try SecureURLPolicy.validate(finalURL)
            }
            var output: [String: Any] = [:]
            if let title = result.title, !title.isEmpty { output["title"] = title }
            if let description = result.description, !description.isEmpty { output["description"] = description }
            if let contentType = result.contentType { output["type"] = contentType }
            output["content"] = Self.wrapUntrusted(await budgetedContent(result.content))
            output["url"] = url

            let limited = await AgenticLoopBudget.shared.limitResult(output)
            await ToolCallReporter.shared.reportResult(name: Self.name, result: limited)
            return limited
        } catch {
            return await reject(
                "Failed to fetch the page: \(error.localizedDescription)",
                hint: "The page could not be loaded (site down, blocked, or no internet). Try a different URL from the search results instead."
            )
        }
    }

    private func reject(_ error: String, hint: String) async -> [String: Any] {
        let err: [String: Any] = [
            "error": String(localized: "\(error)"),
            "hint": hint,
        ]
        await ToolCallReporter.shared.reportResult(name: Self.name, result: err)
        return err
    }

    nonisolated static func wrapUntrusted(_ content: String) -> String {
        "<tool_result source=\"web\" trust=\"untrusted\">\n\(content)\n</tool_result>"
    }

    private func budgetedContent(_ content: String) async -> String {
        let limit = await AgenticLoopBudget.shared.projectedResultLimit()
        var target = min(content.count, max(400, limit * 3))
        var text = SearchResultCompactor.cutAtBoundary(content, maxChars: target)
        var rounds = 0
        while SearchResultCompactor.estimateTokens(of: text) > limit, target > 400, rounds < 6 {
            rounds += 1
            target = max(400, target / 2)
            text = SearchResultCompactor.cutAtBoundary(content, maxChars: target)
        }
        return text
    }
}
