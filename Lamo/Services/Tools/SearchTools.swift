import Foundation
import LiteRTLM

// MARK: - Web Search Tool

struct WebSearchTool: Tool {
    static let name = "web_search"
    static let description = "Search the internet for current information. Returns titles, snippets, and URLs. Use when you need to find facts, news, or verify information."

    @ToolParam(description: "The search query to look up on the internet.")
    var query: String

    @ToolParam(description: "Maximum number of results to return. Default is 5.")
    var maxResults: Int = 5

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(name: Self.name, params: "{\"query\": \"\(query)\", \"maxResults\": \(maxResults)}")

        let searchResults = try await SearchProvider.shared.search(query: query, maxResults: maxResults)
        let shouldFetch = AppDefaults.webAutoFetch.wrappedValue

        let result: Any
        if shouldFetch && !searchResults.isEmpty {
            let topResults = Array(searchResults.prefix(3))
            let urls = topResults.compactMap { result -> URL? in
                guard let urlString = result["url"] else { return nil }
                return URL(string: urlString)
            }

            let fetchedContents = await withTaskGroup(of: (Int, String?).self) { group in
                for (index, url) in urls.enumerated() {
                    group.addTask {
                        do { let c = try await WebFetcher.fetch(url: url); return (index, c) }
                        catch { return (index, nil) }
                    }
                }
                var results: [(Int, String?)] = []
                for await r in group { results.append(r) }
                return results
            }

            var contentMap: [Int: String] = [:]
            for (index, content) in fetchedContents { if let content { contentMap[index] = content } }

            var enrichedResults: [[String: Any]] = []
            for (i, sr) in searchResults.enumerated() {
                var enriched: [String: Any] = ["title": sr["title"] ?? "", "snippet": sr["snippet"] ?? "", "url": sr["url"] ?? ""]
                if let content = contentMap[i] { enriched["content"] = content }
                enrichedResults.append(enriched)
            }
            result = enrichedResults
        } else {
            result = searchResults
        }

        await ToolCallReporter.shared.reportResult(name: Self.name, result: "\(result)")
        return result
    }
}

// MARK: - Fetch URL Tool

struct FetchUrlTool: Tool {
    static let name = "fetch_url"
    static let description = "Fetch and read the content of a specific URL. Returns page title, description, and main content. Use to read articles, documentation, or any specific webpage."

    @ToolParam(description: "The URL to fetch content from.")
    var url: String

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(name: Self.name, params: "{\"url\": \"\(url)\"}")

        guard let fetchURL = URL(string: url) else {
            let err: [String: Any] = ["error": "Invalid URL"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: "\(err)")
            throw FetchError.invalidURL
        }

        if let cached = URLCacheStore.shared.content(for: url) {
            let result: [String: Any] = ["content": cached, "url": url, "source": "cache"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: "\(result)")
            return result
        }

        let result = try await WebFetcher.fetchStructured(url: fetchURL)
        var output: [String: Any] = [:]
        if let title = result.title, !title.isEmpty { output["title"] = title }
        if let description = result.description, !description.isEmpty { output["description"] = description }
        if let contentType = result.contentType { output["type"] = contentType }
        output["content"] = result.content
        output["url"] = url

        if !result.content.isEmpty { URLCacheStore.shared.setContent(result.content, for: url) }

        await ToolCallReporter.shared.reportResult(name: Self.name, result: "\(output)")
        return output
    }
}

enum FetchError: LocalizedError {
    case invalidURL
    case invalidEncoding
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidEncoding: return "Could not decode response"
        }
    }
}
