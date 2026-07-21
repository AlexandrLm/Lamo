import Foundation

// MARK: - Search Provider

/// Multi-provider search with parallel SearXNG merging and DDG HTML fallback.
///
/// Architecture:
/// 1. At init — health-check all SearXNG instances, build live-list
/// 2. On query — parallel query 3 live instances, merge + dedup by URL
/// 3. Smart cache: 5 min TTL for news, 1 hr for facts
/// 4. DDG HTML as reliable fallback
actor SearchProvider {
    static let shared = SearchProvider()

    // MARK: - SearXNG Pool

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

    /// Instances that passed the last health check.
    private var liveInstances: [String] = []
    private var healthCheckDone = false

    // MARK: - Cache

    private var cache: [String: (results: [[String: String]], timestamp: Date, isNews: Bool)] = [:]
    private let newsCacheTTL: TimeInterval = 300     // 5 min for news
    private let factCacheTTL: TimeInterval = 3600     // 1 hr for facts

    /// Keywords that indicate a time-sensitive/news query.
    private static let newsKeywords: Set<String> = [
        "today", "now", "latest", "breaking", "just now", "this week",
        "сегодня", "сейчас", "новости", "последние",
    ]

    // MARK: - Health Tracking

    private var instanceHealth: [String: (failures: Int, lastFail: Date)] = [:]
    private var healthVersion = 0

    // MARK: - Init

    private init() {
        Task { await runHealthCheck() }
    }

    /// Ping all instances with a lightweight query. Fast timeout — dead instances drop quickly.
    func runHealthCheck() async {
        let testQuery = "test"
        var alive: [String] = []

        await withTaskGroup(of: (String, Bool).self) { group in
            for instance in searxngInstances {
                group.addTask {
                    do {
                        let encoded = testQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? testQuery
                        let urlString = "\(instance)/search?q=\(encoded)&format=json&categories=general"
                        guard let url = URL(string: urlString) else { return (instance, false) }

                        var request = URLRequest(url: url)
                        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
                        request.timeoutInterval = 3

                        let (data, _) = try await URLSession.shared.data(for: request)
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              json["results"] != nil else {
                            return (instance, false)
                        }
                        return (instance, true)
                    } catch {
                        return (instance, false)
                    }
                }
            }

            for await (instance, isAlive) in group {
                if isAlive { alive.append(instance) }
            }
        }

        liveInstances = alive
        healthCheckDone = true
    }

    // MARK: - Public API

    var braveAPIKey: String? {
        KeychainHelper.load(key: "brave_search_api_key")
    }

    func search(query: String, maxResults: Int) async throws -> [[String: String]] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isNews = Self.isNewsQuery(normalizedQuery)
        let ttl = isNews ? newsCacheTTL : factCacheTTL

        // Check cache
        if let cached = cache[normalizedQuery],
           Date().timeIntervalSince(cached.timestamp) < ttl {
            return Array(cached.results.prefix(maxResults))
        }

        var results: [[String: String]] = []

        // ── Primary: parallel SearXNG merge ──
        if !liveInstances.isEmpty {
            results = await searchSearxngParallel(query: query, maxResults: maxResults)
        }

        // ── Brave fallback ──
        if results.isEmpty, let apiKey = braveAPIKey, !apiKey.isEmpty {
            do {
                results = try await searchBrave(query: query, maxResults: maxResults, apiKey: apiKey)
            } catch {}
        }

        // ── DDG HTML fallback ──
        if results.isEmpty {
            do {
                results = try await searchDuckDuckGoHTML(query: query, maxResults: maxResults)
            } catch {}
        }

        guard !results.isEmpty else {
            throw SearchError.allProvidersFailed
        }

        cache[normalizedQuery] = (results: results, timestamp: Date(), isNews: isNews)
        return Array(results.prefix(maxResults))
    }

    // MARK: - Query Classification

    private static func isNewsQuery(_ query: String) -> Bool {
        newsKeywords.contains { query.contains($0) }
    }

    // MARK: - SearXNG Parallel Merge

    /// Query up to 3 live instances in parallel, merge results, dedup by URL.
    private func searchSearxngParallel(query: String, maxResults: Int) async -> [[String: String]] {
        let targets = healthyInstances().prefix(3)

        let allResults: [[[String: String]]] = await withTaskGroup(of: [[String: String]].self) { group in
            for instance in targets {
                group.addTask { [self] in
                    do {
                        let r = try await self.searchSearxng(query: query, maxResults: maxResults, instance: instance)
                        return r
                    } catch {
                        return []
                    }
                }
            }

            var collected: [[[String: String]]] = []
            for await result in group {
                if !result.isEmpty { collected.append(result) }
            }
            return collected
        }

        // Merge + dedup by URL
        var seen: Set<String> = []
        var merged: [[String: String]] = []

        // Interleave: take result 0 from each instance, then result 1, etc.
        // This gives diversity instead of one instance dominating.
        let maxIdx = allResults.map(\.count).max() ?? 0
        for i in 0..<maxIdx {
            for instanceResults in allResults {
                guard i < instanceResults.count else { continue }
                let result = instanceResults[i]
                let url = result["url"] ?? ""
                if !seen.contains(url) {
                    seen.insert(url)
                    merged.append(result)
                }
            }
        }

        return merged
    }

    private func searchSearxng(query: String, maxResults: Int, instance: String) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(instance)/search?q=\(encoded)&format=json&categories=general&language=auto"

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
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
            let snippet = (result["content"] as? String) ?? ""
            // Drop results without meaningful snippets
            guard snippet.count >= 30 else { return nil }
            return [
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                "snippet": snippet.trimmingCharacters(in: .whitespacesAndNewlines),
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
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                "snippet": description.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            if let url = result["url"] as? String {
                item["url"] = url
            }
            return item
        }
    }

    // MARK: - DuckDuckGo HTML

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

    // MARK: - DDG HTML Parsing

    private func parseDuckDuckGoResults(html: String, maxResults: Int) -> [[String: String]] {
        var results: [[String: String]] = []
        var seenURLs: Set<String> = []

        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]*)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.*?)</a>"#

        let linkMatches = findMatches(pattern: linkPattern, in: html)
        let snippetMatches = findMatches(pattern: snippetPattern, in: html)

        for (index, match) in linkMatches.enumerated() {
            guard results.count < maxResults else { break }

            guard let redirectURL = extractDuckDuckGoURL(from: match.0),
                  !seenURLs.contains(redirectURL) else { continue }

            seenURLs.insert(redirectURL)

            var result: [String: String] = [
                "title": stripHTML(match.1).trimmingCharacters(in: .whitespacesAndNewlines),
                "url": redirectURL,
            ]

            if index < snippetMatches.count {
                let snippet = stripHTML(snippetMatches[index].1).trimmingCharacters(in: .whitespacesAndNewlines)
                if snippet.count >= 30 {
                    result["snippet"] = snippet
                }
            }

            results.append(result)
        }

        return results
    }

    private func extractDuckDuckGoURL(from redirectURL: String) -> String? {
        if let uddgRange = redirectURL.range(of: "uddg=") {
            let afterUddg = String(redirectURL[uddgRange.upperBound...])
            if let ampRange = afterUddg.range(of: "&") {
                return String(afterUddg[..<ampRange.lowerBound]).removingPercentEncoding
            }
            return afterUddg.removingPercentEncoding
        }
        if redirectURL.hasPrefix("http") {
            return redirectURL
        }
        return nil
    }

    // MARK: - Health Tracking

    private func healthyInstances() -> [String] {
        if healthCheckDone, !liveInstances.isEmpty {
            // Sort live instances by health: fewer failures first
            return liveInstances.sorted { a, b in
                let aFails = instanceHealth[a]?.failures ?? 0
                let bFails = instanceHealth[b]?.failures ?? 0
                return aFails < bFails
            }
        }
        // Fallback: use all instances, sorted by health
        return searxngInstances.sorted { a, b in
            let aFails = instanceHealth[a]?.failures ?? 0
            let bFails = instanceHealth[b]?.failures ?? 0
            return aFails < bFails
        }
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

    // MARK: - Helpers

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
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum SearchError: LocalizedError {
    case invalidURL
    case invalidResponse
    case allProvidersFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid search URL"
        case .invalidResponse: return "Invalid response from search engine"
        case .allProvidersFailed: return "All search providers failed — try again later"
        }
    }
}
