import Foundation
import LiteRTLM
import os

// MARK: - Web Search Tool

/// Tool that allows the model to search the web.
/// Supports SearXNG (primary), Brave Search API (if key configured), DuckDuckGo fallback.
struct WebSearchTool: Tool {
    static let name = "web_search"
    static let description = "Search the internet for current information. Returns titles, snippets, and URLs. Use when you need to find facts, news, or verify information."

    @ToolParam(description: "The search query to look up on the internet.")
    var query: String

    @ToolParam(description: "Maximum number of results to return. Default is 5.")
    var maxResults: Int = 5

    @ToolParam(description: "Automatically fetch full content from top results. Default is true.")
    var fetchTopResults: Bool = true

    func run() async throws -> Any {
        let searchResults = try await SearchProvider.shared.search(query: query, maxResults: maxResults)
        let shouldFetch = UserDefaults.standard.object(forKey: "web_auto_fetch") as? Bool ?? true

        if shouldFetch && !searchResults.isEmpty {
            let topResults = Array(searchResults.prefix(3))
            var enrichedResults: [[String: Any]] = []

            for result in topResults {
                var enriched: [String: Any] = [
                    "title": result["title"] ?? "",
                    "snippet": result["snippet"] ?? "",
                    "url": result["url"] ?? "",
                ]

                if let urlString = result["url"], let url = URL(string: urlString) {
                    do {
                        let content = try await WebFetcher.fetch(url: url)
                        enriched["content"] = content
                    } catch {
                        enriched["content"] = "[Failed to fetch: \(error.localizedDescription)]"
                    }
                }

                enrichedResults.append(enriched)
            }

            if searchResults.count > 3 {
                for result in searchResults.dropFirst(3) {
                    enrichedResults.append(result)
                }
            }

            return enrichedResults
        }

        return searchResults
    }
}

// MARK: - Fetch URL Tool

/// Tool that allows the model to fetch and read content from a specific URL.
/// Returns structured data: metadata (title, description) + page content.
struct FetchUrlTool: Tool {
    static let name = "fetch_url"
    static let description = "Fetch and read the content of a specific URL. Returns page title, description, and main content. Use to read articles, documentation, or any specific webpage."

    @ToolParam(description: "The URL to fetch content from.")
    var url: String

    func run() async throws -> Any {
        guard let fetchURL = URL(string: url) else {
            throw FetchError.invalidURL
        }

        let result = try await WebFetcher.fetchStructured(url: fetchURL)

        var output: [String: Any] = [:]
        if let title = result.title, !title.isEmpty {
            output["title"] = title
        }
        if let description = result.description, !description.isEmpty {
            output["description"] = description
        }
        if let contentType = result.contentType {
            output["type"] = contentType
        }
        output["content"] = result.content
        output["url"] = url

        return output
    }
}

// MARK: - Search Provider

actor SearchProvider {
    static let shared = SearchProvider()

    private var cache: [String: (results: [[String: String]], timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 3600

    // SearXNG public instances (rotated on failure)
    private let searxngInstances = [
        "https://searx.be",
        "https://search.ononoki.org",
        "https://searxng.site",
    ]
    private var currentInstanceIndex = 0

    var braveAPIKey: String? { UserDefaults.standard.string(forKey: "brave_search_api_key") }

    func search(query: String, maxResults: Int) async throws -> [[String: String]] {
        if let cached = cache[query], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return Array(cached.results.prefix(maxResults))
        }

        var results: [[String: String]] = []

        // 1. SearXNG (primary)
        do {
            results = try await searchSearxng(query: query, maxResults: maxResults)
        } catch {
            LamoLogger.general.warning("SearXNG failed: \(error.localizedDescription), trying Brave/DuckDuckGo")
        }

        // 2. Brave (fallback if SearXNG failed and key is set)
        if results.isEmpty, let apiKey = braveAPIKey, !apiKey.isEmpty {
            do {
                results = try await searchBrave(query: query, maxResults: maxResults, apiKey: apiKey)
            } catch {
                LamoLogger.general.warning("Brave failed: \(error.localizedDescription)")
            }
        }

        // 3. DuckDuckGo (last resort)
        if results.isEmpty {
            do {
                results = try await searchDuckDuckGo(query: query, maxResults: maxResults)
            } catch {
                LamoLogger.general.error("All search providers failed")
                throw error
            }
        }

        cache[query] = (results: results, timestamp: Date())
        return results
    }

    // MARK: - SearXNG

    private func searchSearxng(query: String, maxResults: Int) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let instance = searxngInstances[currentInstanceIndex % searxngInstances.count]
        let urlString = "\(instance)/search?q=\(encoded)&format=json&categories=general"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS AI Chat)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultsArray = json["results"] as? [[String: Any]] else {
            // Rotate instance on invalid response
            currentInstanceIndex += 1
            throw SearchError.invalidResponse
        }

        return resultsArray.prefix(maxResults).compactMap { result in
            guard let title = result["title"] as? String,
                  let url = result["url"] as? String else { return nil }
            return [
                "title": title,
                "snippet": result["content"] as? String ?? "",
                "url": url,
            ]
        }
    }

    // MARK: - Brave Search API

    private func searchBrave(query: String, maxResults: Int, apiKey: String) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=\(maxResults)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "X-Subscription-Token")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            throw SearchError.invalidResponse
        }

        return results.prefix(maxResults).compactMap { result in
            guard let title = result["title"] as? String,
                  let description = result["description"] as? String else { return nil }

            var item: [String: String] = [
                "title": title,
                "snippet": description,
            ]
            if let url = result["url"] as? String {
                item["url"] = url
            }
            return item
        }
    }

    // MARK: - DuckDuckGo Fallback

    private func searchDuckDuckGo(query: String, maxResults: Int) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://html.duckduckgo.com/html/?q=\(encoded)&kl=wt-wt"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidResponse
        }

        return parseDuckDuckGoResults(html: html, maxResults: maxResults)
    }

    private func parseDuckDuckGoResults(html: String, maxResults: Int) -> [[String: String]] {
        var results: [[String: String]] = []

        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.*?)</a>"#

        let linkMatches = findMatches(pattern: linkPattern, in: html)
        let snippetMatches = findMatches(pattern: snippetPattern, in: html)

        for (index, match) in linkMatches.prefix(maxResults).enumerated() {
            var result: [String: String] = [:]

            if let redirectURL = extractDuckDuckGoURL(from: match.0) {
                result["url"] = redirectURL
            }

            result["title"] = stripHTML(match.1)

            if index < snippetMatches.count {
                result["snippet"] = stripHTML(snippetMatches[index].1)
            }

            results.append(result)
        }

        return results
    }

    private func extractDuckDuckGoURL(from redirectURL: String) -> String? {
        if let uddgRange = redirectURL.range(of: "uddg=") {
            let afterUddg = String(redirectURL[uddgRange.upperBound...])
            if let ampRange = afterUddg.range(of: "&") {
                let encoded = String(afterUddg[..<ampRange.lowerBound])
                return encoded.removingPercentEncoding
            }
            return afterUddg.removingPercentEncoding
        }
        if redirectURL.hasPrefix("http") {
            return redirectURL
        }
        return nil
    }

    private func findMatches(pattern: String, in text: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match -> (String, String)? in
            guard match.numberOfRanges > 2,
                  let r0 = Range(match.range(at: 0), in: text),
                  let r1 = Range(match.range(at: 1), in: text),
                  let r2 = Range(match.range(at: 2), in: text) else { return nil }
            return (String(text[r0]), String(text[r1]) + "|||" + String(text[r2]))
        }
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SearchError: LocalizedError {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid search URL"
        case .invalidResponse: return "Invalid response from search engine"
        }
    }
}

// MARK: - Web Fetcher

struct PageMetadata {
    let title: String?
    let description: String?
    let contentType: String?
    let content: String
}

actor WebFetcher {
    static let shared = WebFetcher()
    private static let maxConcurrent = 3
    private static var activeTasks = 0
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    /// Fetch a URL and return plain text content.
    static func fetch(url: URL) async throws -> String {
        let result = try await fetchStructured(url: url)
        return result.content
    }

    /// Fetch a URL and return structured metadata + content.
    static func fetchStructured(url: URL) async throws -> PageMetadata {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await WebFetcher.shared.enqueue(continuation)
            }
        }

        defer {
            Task {
                await WebFetcher.shared.releaseSlot()
            }
        }

        var lastError: Error?
        for attempt in 0..<2 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(1))
            }
            do {
                return try await fetchOnceStructured(url: url)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FetchError.invalidEncoding
    }

    private func enqueue(_ continuation: CheckedContinuation<Void, Never>) {
        if Self.activeTasks < Self.maxConcurrent {
            Self.activeTasks += 1
            continuation.resume()
        } else {
            Self.waiters.append(continuation)
        }
    }

    private func releaseSlot() {
        Self.activeTasks -= 1
        if !Self.waiters.isEmpty {
            Self.activeTasks += 1
            Self.waiters.removeFirst().resume()
        }
    }

    private static func fetchOnceStructured(url: URL) async throws -> PageMetadata {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }

        let metadata = extractMetadata(from: html)
        let content = extractText(from: html)

        let maxLength = 4000
        let truncatedContent: String
        if content.count > maxLength {
            truncatedContent = String(content.prefix(maxLength)) + "\n\n[Content truncated at \(maxLength) chars]"
        } else {
            truncatedContent = content
        }

        return PageMetadata(
            title: metadata.title,
            description: metadata.description,
            contentType: metadata.contentType,
            content: truncatedContent
        )
    }

    // MARK: - Metadata Extraction

    private struct RawMetadata {
        var title: String?
        var description: String?
        var contentType: String?
    }

    private static func extractMetadata(from html: String) -> RawMetadata {
        var meta = RawMetadata()

        // Extract <title>
        if let titleRange = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: .regularExpression) {
            let titleHTML = String(html[titleRange])
            meta.title = stripTags(titleHTML)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract meta description (og:description first, then standard)
        meta.description = extractMetaContent(from: html, property: "og:description")
            ?? extractMetaContent(from: html, property: "description")

        // Override title with og:title if available
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            meta.title = ogTitle
        }

        // Detect content type from og:type or page structure
        if let ogType = extractMetaContent(from: html, property: "og:type") {
            meta.contentType = ogType
        } else if html.contains("<article") {
            meta.contentType = "article"
        } else if html.contains("<pre") || html.contains("<code") {
            meta.contentType = "code"
        } else if html.contains("api") || html.contains("endpoint") {
            meta.contentType = "documentation"
        }

        return meta
    }

    private static func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            #"<meta[^>]*property="\#(property)"[^>]*content="([^"]*)""#,
            #"<meta[^>]*content="([^"]*)"[^>]*property="\#(property)""#,
            #"<meta[^>]*name="\#(property)"[^>]*content="([^"]*)""#,
            #"<meta[^>]*content="([^"]*)"[^>]*name="\#(property)""#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range),
                   match.numberOfRanges > 2,
                   let contentRange = Range(match.range(at: 2), in: html) {
                    let value = String(html[contentRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    private static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }

    private static func extractText(from html: String) -> String {
        // Remove non-content elements before stripping tags
        var text = html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<nav[^>]*>[\\s\\S]*?</nav>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<footer[^>]*>[\\s\\S]*?</footer>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<header[^>]*>[\\s\\S]*?</header>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<aside[^>]*>[\\s\\S]*?</aside>", with: "", options: .regularExpression)

        // Try to extract article/main content first
        if let articleRange = text.range(of: "<article[^>]*>([\\s\\S]*?)</article>", options: .regularExpression) {
            text = String(text[articleRange])
        } else if let mainRange = text.range(of: "<main[^>]*>([\\s\\S]*?)</main>", options: .regularExpression) {
            text = String(text[mainRange])
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
