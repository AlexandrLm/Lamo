import Foundation
import LiteRTLM

// MARK: - Web Search Tool

/// Tool that allows the model to search the web.
/// Supports Brave Search API (if key configured) or DuckDuckGo fallback.
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
        // 1. Search
        let searchResults = try await SearchProvider.shared.search(query: query, maxResults: maxResults)

        // 2. Optionally fetch full content from top results
        if fetchTopResults && !searchResults.isEmpty {
            let topResults = Array(searchResults.prefix(3))
            var enrichedResults: [[String: Any]] = []

            for result in topResults {
                var enriched: [String: Any] = [
                    "title": result["title"] ?? "",
                    "snippet": result["snippet"] ?? "",
                    "url": result["url"] ?? "",
                ]

                // Fetch full page content
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

            // Add remaining results without content
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

/// Tool that allows the model to fetch content from a specific URL.
struct FetchUrlTool: Tool {
    static let name = "fetch_url"
    static let description = "Fetch and read the content of a specific URL. Use this to get detailed information from a webpage."

    @ToolParam(description: "The URL to fetch content from.")
    var url: String

    func run() async throws -> Any {
        guard let fetchURL = URL(string: url) else {
            throw FetchError.invalidURL
        }
        let content = try await WebFetcher.fetch(url: fetchURL)
        return content
    }
}

// MARK: - Search Provider (Brave API + DuckDuckGo fallback)

actor SearchProvider {
    static let shared = SearchProvider()

    private var braveAPIKey: String? { UserDefaults.standard.string(forKey: "brave_search_api_key") }
    private var cache: [String: (results: [[String: String]], timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    func search(query: String, maxResults: Int) async throws -> [[String: String]] {
        // Check cache
        if let cached = cache[query], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return Array(cached.results.prefix(maxResults))
        }

        let results: [[String: String]]

        if let apiKey = braveAPIKey, !apiKey.isEmpty {
            results = try await searchBrave(query: query, maxResults: maxResults, apiKey: apiKey)
        } else {
            results = try await searchDuckDuckGo(query: query, maxResults: maxResults)
        }

        // Cache results
        cache[query] = (results: results, timestamp: Date())

        return results
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

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidResponse
        }

        return parseDuckDuckGoResults(html: html, maxResults: maxResults)
    }

    private func parseDuckDuckGoResults(html: String, maxResults: Int) -> [[String: String]] {
        var results: [[String: String]] = []

        // Extract result links with URLs
        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.*?)</a>"#

        let linkMatches = findMatches(pattern: linkPattern, in: html)
        let snippetMatches = findMatches(pattern: snippetPattern, in: html)

        for (index, match) in linkMatches.prefix(maxResults).enumerated() {
            var result: [String: String] = [:]

            // Extract URL from DuckDuckGo redirect
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

    /// Extract actual URL from DuckDuckGo's redirect URL
    private func extractDuckDuckGoURL(from redirectURL: String) -> String? {
        // DuckDuckGo format: //duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com&rut=...
        if let uddgRange = redirectURL.range(of: "uddg=") {
            let afterUddg = String(redirectURL[uddgRange.upperBound...])
            if let ampRange = afterUddg.range(of: "&") {
                let encoded = String(afterUddg[..<ampRange.lowerBound])
                return encoded.removingPercentEncoding
            }
            return afterUddg.removingPercentEncoding
        }
        // Direct URL
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

actor WebFetcher {
    static func fetch(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }

        let text = extractText(from: html)

        // Truncate to reasonable length for the model
        let maxLength = 4000
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "\n\n[Content truncated at \(maxLength) chars]"
        }
        return text
    }

    private static func extractText(from html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

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
