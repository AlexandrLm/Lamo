import Foundation
import LiteRTLM
import os

// MARK: - URL Content Cache

/// Simple in-memory cache for fetched URL contents to avoid re-fetching the same URL within a conversation.
final class URLCacheStore {
    static let shared = URLCacheStore()
    private let cache = NSCache<NSString, NSString>()
    private init() {
        cache.countLimit = 50
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB
    }

    func content(for url: String) -> String? {
        cache.object(forKey: url as NSString) as String?
    }

    func setContent(_ content: String, for url: String) {
        cache.setObject(content as NSString, forKey: url as NSString, cost: content.utf8.count)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

// MARK: - Web Search Tool

struct WebSearchTool: Tool {
    static let name = "web_search"
    static let description = "Search the internet for current information. Returns titles, snippets, and URLs. Use when you need to find facts, news, or verify information."

    @ToolParam(description: "The search query to look up on the internet.")
    var query: String

    @ToolParam(description: "Maximum number of results to return. Default is 5.")
    var maxResults: Int = 5

    func run() async throws -> Any {
        let searchResults = try await SearchProvider.shared.search(query: query, maxResults: maxResults)
        let shouldFetch = UserDefaults.standard.object(forKey: "web_auto_fetch") as? Bool ?? true

        if shouldFetch && !searchResults.isEmpty {
            let topResults = Array(searchResults.prefix(3))
            let urls = topResults.compactMap { result -> URL? in
                guard let urlString = result["url"] else { return nil }
                return URL(string: urlString)
            }

            let fetchedContents = await withTaskGroup(of: (Int, String?).self) { group in
                for (index, url) in urls.enumerated() {
                    group.addTask {
                        do {
                            let content = try await WebFetcher.fetch(url: url)
                            return (index, content)
                        } catch {
                            return (index, nil)
                        }
                    }
                }
                var results: [(Int, String?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            var contentMap: [Int: String] = [:]
            for (index, content) in fetchedContents {
                if let content { contentMap[index] = content }
            }

            var enrichedResults: [[String: Any]] = []
            for (i, result) in searchResults.enumerated() {
                var enriched: [String: Any] = [
                    "title": result["title"] ?? "",
                    "snippet": result["snippet"] ?? "",
                    "url": result["url"] ?? "",
                ]
                if let content = contentMap[i] {
                    enriched["content"] = content
                }
                enrichedResults.append(enriched)
            }

            return enrichedResults
        }

        return searchResults
    }
}

// MARK: - Fetch URL Tool

struct FetchUrlTool: Tool {
    static let name = "fetch_url"
    static let description = "Fetch and read the content of a specific URL. Returns page title, description, and main content. Use to read articles, documentation, or any specific webpage."

    @ToolParam(description: "The URL to fetch content from.")
    var url: String

    func run() async throws -> Any {
        guard let fetchURL = URL(string: url) else {
            throw FetchError.invalidURL
        }

        // Check cache first — avoids re-fetching the same URL within a conversation
        if let cached = URLCacheStore.shared.content(for: url) {
            return [
                "content": cached,
                "url": url,
                "source": "cache"
            ] as [String: Any]
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

        // Cache the fetched content
        if !result.content.isEmpty {
            URLCacheStore.shared.setContent(result.content, for: url)
        }

        return output
    }
}

// MARK: - Deep Research Tool

struct DeepResearchTool: Tool {
    static let name = "deep_research"
    static let description = "Perform multi-step research on a topic. Searches multiple queries, reads top sources, and returns structured findings. Use for complex questions, fact-checking, comparisons, or when you need thorough analysis from multiple sources."

    @ToolParam(description: "The research question or topic to investigate.")
    var question: String

    @ToolParam(description: "Comma-separated search queries to try. Generate 2-4 different queries that approach the topic from different angles.")
    var queries: String

    func run() async throws -> Any {
        let queryList = queries.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !queryList.isEmpty else {
            throw ResearchError.noQueries
        }

        let allResults = await withTaskGroup(of: [[String: String]].self) { group in
            for query in queryList.prefix(4) {
                group.addTask {
                    do {
                        return try await SearchProvider.shared.search(query: String(query), maxResults: 4)
                    } catch {
                        return []
                    }
                }
            }
            var combined: [[String: String]] = []
            for await results in group {
                combined.append(contentsOf: results)
            }
            return combined
        }

        var seen = Set<String>()
        var uniqueResults: [[String: String]] = []
        for result in allResults {
            guard let url = result["url"], !seen.contains(url) else { continue }
            seen.insert(url)
            uniqueResults.append(result)
        }

        let toFetch = Array(uniqueResults.prefix(5))
        let urls = toFetch.compactMap { r -> URL? in
            guard let s = r["url"] else { return nil }
            return URL(string: s)
        }

        let fetched = await withTaskGroup(of: (Int, String?).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask {
                    do {
                        let content = try await WebFetcher.fetch(url: url)
                        return (i, content)
                    } catch {
                        return (i, nil)
                    }
                }
            }
            var results: [(Int, String?)] = []
            for await r in group { results.append(r) }
            return results
        }

        var contentMap: [Int: String] = [:]
        for (i, c) in fetched { if let c { contentMap[i] = c } }

        var findings: [[String: Any]] = []
        for (i, result) in toFetch.enumerated() {
            var finding: [String: Any] = [
                "title": result["title"] ?? "",
                "url": result["url"] ?? "",
                "snippet": result["snippet"] ?? "",
            ]
            if let content = contentMap[i] {
                finding["content"] = content
            }
            findings.append(finding)
        }

        return [
            "question": question,
            "queries_used": queryList,
            "sources_found": uniqueResults.count,
            "sources_read": contentMap.count,
            "findings": findings,
        ]
    }
}

enum ResearchError: LocalizedError {
    case noQueries
    var errorDescription: String? { "No search queries provided" }
}

// MARK: - Search Provider

actor SearchProvider {
    static let shared = SearchProvider()

    private var cache: [String: (results: [[String: String]], timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 3600

    // SearXNG public instances — large pool for rotation
    private let searxngInstances = [
        "https://searx.be",
        "https://search.ononoki.org",
        "https://searxng.site",
        "https://search.sapti.me",
        "https://priv.au",
        "https://searx.tuxcloud.net",
        "https://search.bus-hit.me",
        "https://searx.tiekoetter.com",
        "https://search.hbubli.cc",
        "https://searx.namejeff.xyz",
        "https://search.rhscz.eu",
        "https://sx.catgirl.cloud",
        "https://searx.juancord.xyz",
        "https://searx.ericaftereric.top",
        "https://search.suenorth.org",
        "https://searxng.ch",
        "https://search.mdosch.de",
        "https://searx.zhenyapav.com",
    ]

    // Health tracking: instance -> (failures, lastFail)
    private var instanceHealth: [String: (failures: Int, lastFail: Date)] = [:]
    private var currentInstanceIndex = 0
    /// Cached sorted instance list — recomputed only when health changes.
    private var healthyOrderCache: [String] = []
    /// Monotonically increasing version bumped on every health mutation.
    private var healthVersion = 0
    /// The healthVersion at which healthyOrderCache was last computed.
    private var lastSortedHealthVersion = -1

    var braveAPIKey: String? {
        get { KeychainHelper.load(key: "brave_search_api_key") }
    }

    func search(query: String, maxResults: Int) async throws -> [[String: String]] {
        let cacheKey = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return Array(cached.results.prefix(maxResults))
        }

        // Sort instances: prefer healthy ones, avoid recently failed
        let sortedInstances = healthyInstances()
        var results: [[String: String]] = []

        // Try up to 5 SearXNG instances in parallel (first 3 that succeed)
        results = await withTaskGroup(of: [[String: String]]?.self) { group in
            var found: [[String: String]] = []
            let toTry = Array(sortedInstances.prefix(5))

            for (_, instance) in toTry.enumerated() {
                group.addTask { [self] in
                    do {
                        let r = try await self.searchSearxng(query: query, maxResults: maxResults, instance: instance)
                        return r.isEmpty ? nil : r
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let r = result, !r.isEmpty, found.isEmpty {
                    found = r
                    // Cancel remaining
                    group.cancelAll()
                }
            }
            return found
        }

        // Brave fallback (if key configured)
        if results.isEmpty, let apiKey = braveAPIKey, !apiKey.isEmpty {
            do {
                results = try await searchBrave(query: query, maxResults: maxResults, apiKey: apiKey)
            } catch {}
        }

        // DuckDuckGo fallback
        if results.isEmpty {
            do {
                results = try await searchDuckDuckGo(query: query, maxResults: maxResults)
            } catch {}
        }

        // DuckDuckGo HTML fallback
        if results.isEmpty {
            do {
                results = try await searchDuckDuckGoHTML(query: query, maxResults: maxResults)
            } catch {}
        }

        // Google scrape fallback
        if results.isEmpty {
            do {
                results = try await searchGoogle(query: query, maxResults: maxResults)
            } catch {}
        }

        guard !results.isEmpty else {
            throw SearchError.allProvidersFailed
        }

        cache[cacheKey] = (results: results, timestamp: Date())
        return Array(results.prefix(maxResults))
    }

    // MARK: - Health Tracking

    private func healthyInstances() -> [String] {
        // Use cached order unless health data has changed since last sort
        if !healthyOrderCache.isEmpty, lastSortedHealthVersion == healthVersion {
            return healthyOrderCache
        }

        let now = Date()
        let sorted = searxngInstances.sorted { a, b in
            let aHealth = instanceHealth[a]
            let bHealth = instanceHealth[b]
            // Instances that failed recently (within 5 min) go last
            let aRecentFail = aHealth.map { $0.failures > 0 && now.timeIntervalSince($0.lastFail) < 300 } ?? false
            let bRecentFail = bHealth.map { $0.failures > 0 && now.timeIntervalSince($0.lastFail) < 300 } ?? false
            if aRecentFail != bRecentFail { return !aRecentFail }
            // Fewer failures first
            let aFails = aHealth?.failures ?? 0
            let bFails = bHealth?.failures ?? 0
            return aFails < bFails
        }
        healthyOrderCache = sorted
        lastSortedHealthVersion = healthVersion
        return sorted
    }

    private func markFailed(_ instance: String) {
        let current = instanceHealth[instance]
        instanceHealth[instance] = (
            failures: (current?.failures ?? 0) + 1,
            lastFail: Date()
        )
        healthVersion += 1
    }

    private func markSuccess(_ instance: String) {
        instanceHealth[instance] = (failures: 0, lastFail: Date())
        healthVersion += 1
    }

    // MARK: - SearXNG

    private func searchSearxng(query: String, maxResults: Int, instance: String) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(instance)/search?q=\(encoded)&format=json&categories=general&language=auto"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultsArray = json["results"] as? [[String: Any]] else {
            markFailed(instance)
            throw SearchError.invalidResponse
        }

        markSuccess(instance)

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
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.timeoutInterval = 10

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

    // MARK: - DuckDuckGo (API-based, not HTML scraping)

    private func searchDuckDuckGo(query: String, maxResults: Int) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SearchError.invalidResponse
        }

        var results: [[String: String]] = []

        // Abstract (main result)
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty,
           let heading = json["Heading"] as? String, !heading.isEmpty,
           let abstractURL = json["AbstractURL"] as? String {
            results.append([
                "title": heading,
                "snippet": abstract,
                "url": abstractURL,
            ])
        }

        // Related topics
        if let topics = json["RelatedTopics"] as? [[String: Any]] {
            for topic in topics.prefix(maxResults) {
                if let text = topic["Text"] as? String, !text.isEmpty,
                   let firstURL = topic["FirstURL"] as? String {
                    let title = String(text.prefix(80))
                    results.append([
                        "title": title,
                        "snippet": text,
                        "url": firstURL,
                    ])
                }
                // Nested sub-topics
                if let subTopics = topic["Topics"] as? [[String: Any]] {
                    for sub in subTopics.prefix(2) {
                        if let text = sub["Text"] as? String, !text.isEmpty,
                           let firstURL = sub["FirstURL"] as? String {
                            results.append([
                                "title": String(text.prefix(80)),
                                "snippet": text,
                                "url": firstURL,
                            ])
                        }
                    }
                }
            }
        }

        // If API returned nothing useful, fall back to HTML
        if results.isEmpty {
            return try await searchDuckDuckGoHTML(query: query, maxResults: maxResults)
        }

        return Array(results.prefix(maxResults))
    }

    // MARK: - DuckDuckGo HTML Fallback

    private func searchDuckDuckGoHTML(query: String, maxResults: Int) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://html.duckduckgo.com/html/?q=\(encoded)&kl=wt-wt"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidResponse
        }

        return parseDuckDuckGoResults(html: html, maxResults: maxResults)
    }

    // MARK: - Google (scrape)

    private func searchGoogle(query: String, maxResults: Int) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://www.google.com/search?q=\(encoded)&num=\(maxResults)"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidResponse
        }

        return parseGoogleResults(html: html, maxResults: maxResults)
    }

    private func parseGoogleResults(html: String, maxResults: Int) -> [[String: String]] {
        var results: [[String: String]] = []

        // Google result pattern: <a href="/url?q=ACTUAL_URL&...">
        let urlPattern = #"<a href="/url\?q=([^&"]+)[^"]*"[^>]*>"#
        let titlePattern = #"<h3[^>]*>(.*?)</h3>"#

        guard let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive),
              let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return results
        }

        let range = NSRange(html.startIndex..., in: html)
        let urlMatches = urlRegex.matches(in: html, options: [], range: range)
        let titleMatches = titleRegex.matches(in: html, options: [], range: range)

        for i in 0..<min(urlMatches.count, titleMatches.count, maxResults) {
            guard let urlRange = Range(urlMatches[i].range(at: 1), in: html),
                  let titleRange = Range(titleMatches[i].range(at: 1), in: html) else { continue }

            let urlString = String(html[urlRange])
                .replacingOccurrences(of: "&amp;", with: "&")

            guard let decodedURL = urlString.removingPercentEncoding,
                  decodedURL.hasPrefix("http") else { continue }

            let title = stripHTML(String(html[titleRange]))

            results.append([
                "title": title,
                "snippet": "",
                "url": decodedURL,
            ])
        }

        return results
    }

    // MARK: - DDG HTML Parsing

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
                  let r1 = Range(match.range(at: 1), in: text),
                  let r2 = Range(match.range(at: 2), in: text) else { return nil }
            return (String(text[r1]), String(text[r2]))
        }
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SearchError: LocalizedError {
    case invalidURL
    case invalidResponse
    case allProvidersFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid search URL"
        case .invalidResponse: return "Invalid response from search engine"
        case .allProvidersFailed: return "All search providers failed"
        }
    }
}

// MARK: - Web Fetcher (Readability-based)

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

    // Content cache (per session)
    private static var contentCache: [String: (content: String, timestamp: Date)] = [:]
    private static let contentCacheTTL: TimeInterval = 1800 // 30 min

    /// Fetch a URL and return plain text content.
    static func fetch(url: URL) async throws -> String {
        let result = try await fetchStructured(url: url)
        return result.content
    }

    /// Fetch a URL and return structured metadata + content.
    static func fetchStructured(url: URL) async throws -> PageMetadata {
        let cacheKey = url.absoluteString
        if let cached = contentCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < contentCacheTTL {
            return PageMetadata(title: nil, description: nil, contentType: nil, content: cached.content)
        }

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
                let result = try await fetchOnceStructured(url: url)
                contentCache[cacheKey] = (content: result.content, timestamp: Date())
                return result
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
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        let mimeType = (response as? HTTPURLResponse)?.mimeType ?? ""
        let isPDF = mimeType.contains("pdf") || url.pathExtension == "pdf"

        if isPDF {
            return PageMetadata(
                title: url.lastPathComponent,
                description: nil,
                contentType: "pdf",
                content: "[PDF document — cannot extract text from \(url.absoluteString)]"
            )
        }

        guard let html = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .ascii) else {
            throw FetchError.invalidEncoding
        }

        let metadata = extractMetadata(from: html)
        let content = extractReadableContent(from: html)

        let maxLength = 6000
        let truncatedContent: String
        if content.count > maxLength {
            // Try to truncate at sentence boundary
            let truncated = String(content.prefix(maxLength))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                truncatedContent = String(truncated[...lastPeriod])
            } else {
                truncatedContent = truncated + "\n\n[Content truncated at \(maxLength) chars]"
            }
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

    // MARK: - Readability-based Content Extraction

    /// Extract meaningful content using a readability-inspired algorithm.
    /// Preserves paragraph structure and removes boilerplate.
    private static func extractReadableContent(from html: String) -> String {
        var text = html

        // Phase 1: Remove non-content elements
        let removePatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<noscript[^>]*>[\\s\\S]*?</noscript>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<aside[^>]*>[\\s\\S]*?</aside>",
            "<form[^>]*>[\\s\\S]*?</form>",
            "<iframe[^>]*>[\\s\\S]*?</iframe>",
            "<svg[^>]*>[\\s\\S]*?</svg>",
            "<!--[\\s\\S]*?-->",
            "<button[^>]*>[\\s\\S]*?</button>",
        ]
        for pattern in removePatterns {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        // Phase 2: Convert structural elements to text markers BEFORE stripping tags
        // This preserves paragraph structure
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: .regularExpression)

        // Headings get special markers
        text = text.replacingOccurrences(of: "<h1[^>]*>", with: "\n# ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<h2[^>]*>", with: "\n## ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<h3[^>]*>", with: "\n### ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<h[4-6][^>]*>", with: "\n#### ", options: .regularExpression)

        // List items
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)

        // Phase 3: Extract article/main content if available
        let contentPatterns = [
            #"<article[^>]*>([\s\S]*?)</article>"#,
            #"<main[^>]*>([\s\S]*?)</main>"#,
            #"<div[^>]*class="[^"]*content[^"]*"[^>]*>([\s\S]*?)</div>"#,
            #"<div[^>]*class="[^"]*article[^"]*"[^>]*>([\s\S]*?)</div>"#,
            #"<div[^>]*class="[^"]*post[^"]*"[^>]*>([\s\S]*?)</div>"#,
            #"<div[^>]*role="main"[^>]*>([\s\S]*?)</div>"#,
        ]

        var extractedContent: String?
        for pattern in contentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range),
                   match.numberOfRanges > 1,
                   let contentRange = Range(match.range(at: 1), in: text) {
                    extractedContent = String(text[contentRange])
                    break
                }
            }
        }

        if let extracted = extractedContent {
            text = extracted
        }

        // Phase 4: Strip remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Phase 5: Decode HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#x27;", "'"), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
            ("&laquo;", "«"), ("&raquo;", "»"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
            ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities
        if let entityRegex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = entityRegex.matches(in: text, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let numRange = Range(match.range(at: 1), in: text),
                      let codePoint = UInt32(String(text[numRange])),
                      let scalar = Unicode.Scalar(codePoint),
                      let fullRange = Range(match.range, in: text) else { continue }
                text.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }

        // Phase 6: Clean up whitespace while preserving paragraph structure
        // Collapse multiple spaces to single
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        // Collapse 3+ newlines to 2
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        // Trim each line
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        text = lines.joined(separator: "\n")
        // Collapse multiple blank lines again
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        // Phase 7: Remove very short lines (likely noise) but keep headings
        let cleanedLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let s = line.trimmingCharacters(in: .whitespaces)
                if s.isEmpty { return true } // Keep blank lines for paragraph breaks
                if s.hasPrefix("#") { return true } // Keep headings
                if s.hasPrefix("- ") { return true } // Keep list items
                return s.count >= 10 // Remove very short fragments
            }
        text = cleanedLines.joined(separator: "\n")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // Extract meta description
        meta.description = extractMetaContent(from: html, property: "og:description")
            ?? extractMetaContent(from: html, property: "description")

        // Override title with og:title if available
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            meta.title = ogTitle
        }

        // Detect content type
        if let ogType = extractMetaContent(from: html, property: "og:type") {
            meta.contentType = ogType
        } else if html.contains("<article") {
            meta.contentType = "article"
        } else if html.contains("<pre") || html.contains("<code") {
            meta.contentType = "code"
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
