import Foundation
import LiteRTLM

/// Tool that allows the model to search the web via DuckDuckGo.
struct WebSearchTool: Tool {
    static let name = "web_search"
    static let description = "Search the internet for current information. Use this when you need to find facts, news, or verify information."

    @ToolParam(description: "The search query to look up on the internet.")
    var query: String

    @ToolParam(description: "Maximum number of results to return. Default is 5.")
    var maxResults: Int = 5

    func run() async throws -> Any {
        let results = try await DuckDuckGoSearch.search(query: query, maxResults: maxResults)
        return results
    }
}

/// Tool that allows the model to fetch content from a specific URL.
struct FetchUrlTool: Tool {
    static let name = "fetch_url"
    static let description = "Fetch and read the content of a specific URL. Use this to get detailed information from a webpage."

    @ToolParam(description: "The URL to fetch content from.")
    var url: String

    func run() async throws -> Any {
        let content = try await WebFetcher.fetch(url: url)
        return content
    }
}

// MARK: - DuckDuckGo Search

actor DuckDuckGoSearch {
    static func search(query: String, maxResults: Int) async throws -> [[String: String]] {
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

        return parseResults(html: html, maxResults: maxResults)
    }

    private static func parseResults(html: String, maxResults: Int) -> [[String: String]] {
        var results: [[String: String]] = []

        // Parse result blocks from DuckDuckGo HTML
        let resultPattern = #"<a rel="nofollow" class="result__a" href="[^"]*"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.*?)</a>"#

        let resultMatches = findMatches(pattern: resultPattern, in: html)
        let snippetMatches = findMatches(pattern: snippetPattern, in: html)

        for (index, title) in resultMatches.prefix(maxResults).enumerated() {
            var result: [String: String] = [:]
            result["title"] = stripHTML(title)

            if index < snippetMatches.count {
                result["snippet"] = stripHTML(snippetMatches[index])
            }

            results.append(result)
        }

        return results
    }

    private static func findMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match -> String? in
            // Capture group 1 (the content inside the tag)
            if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
            return nil
        }
    }

    private static func stripHTML(_ html: String) -> String {
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
    static func fetch(url: String) async throws -> String {
        guard let fetchURL = URL(string: url) else {
            throw FetchError.invalidURL
        }

        var request = URLRequest(url: fetchURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }

        // Extract text content, stripping HTML tags
        let text = extractText(from: html)

        // Truncate to reasonable length for the model
        let maxLength = 3000
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "\n\n[Content truncated...]"
        }
        return text
    }

    private static func extractText(from html: String) -> String {
        // Remove script and style tags
        var text = html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
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
