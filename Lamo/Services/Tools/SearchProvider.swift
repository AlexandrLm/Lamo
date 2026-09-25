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
    /// Throttle for opportunistic pool refreshes (see `search`).
    private var lastHealthCheck = Date.distantPast

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
        lastHealthCheck = Date()
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

        // An empty result means the check itself failed (no network, captive portal) —
        // keep the last-known-good list instead of wiping it.
        if !alive.isEmpty {
            liveInstances = alive
        }
        healthCheckDone = true
        lastHealthCheck = Date()
    }

    /// Refresh the pool without blocking the query: a stale live-list makes every
    /// search pay dead-instance timeouts, but a refresh must never stall an answer.
    /// Throttled — at most one background refresh per 10 minutes.
    private func refreshPoolIfStale() {
        guard Date().timeIntervalSince(lastHealthCheck) > 600 else { return }
        lastHealthCheck = Date()
        Task { await self.runHealthCheck() }
    }

    // MARK: - Public API

    var braveAPIKey: String? {
        KeychainHelper.load(key: "brave_search_api_key")
    }

    func search(query: String, maxResults: Int, timeRange: String? = nil) async throws -> [[String: String]] {
        let normalizedQuery = SearchResultCompactor.sanitizeQuery(query).lowercased()
        guard !normalizedQuery.isEmpty else { throw SearchError.emptyQuery }
        let isNews = Self.isNewsQuery(normalizedQuery)
        let ttl = isNews ? newsCacheTTL : factCacheTTL
        let cacheKey = timeRange.map { "\(normalizedQuery)|\($0)" } ?? normalizedQuery

        // Check cache
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < ttl {
            return Array(cached.results.prefix(maxResults))
        }

        refreshPoolIfStale()

        var results: [[String: String]] = []

        // ── Primary: parallel SearXNG merge ──
        if !liveInstances.isEmpty {
            results = await searchSearxngParallel(query: query, maxResults: maxResults, timeRange: timeRange)
        }

        // ── Brave fallback ──
        if results.isEmpty, let apiKey = braveAPIKey, !apiKey.isEmpty {
            do {
                results = try await searchBrave(query: query, maxResults: maxResults, apiKey: apiKey, timeRange: timeRange)
            } catch {}
        }

        // ── DDG HTML fallback ──
        if results.isEmpty {
            do {
                results = try await searchDuckDuckGoHTML(query: query, maxResults: maxResults, timeRange: timeRange)
            } catch {}
        }

        guard !results.isEmpty else {
            throw SearchError.allProvidersFailed
        }

        // Bound cache growth — evict the oldest entries first.
        if cache.count >= 50 {
            let oldest = cache.sorted { $0.value.timestamp < $1.value.timestamp }.prefix(10).map(\.key)
            for key in oldest { cache.removeValue(forKey: key) }
        }
        cache[cacheKey] = (results: results, timestamp: Date(), isNews: isNews)
        return Array(results.prefix(maxResults))
    }

    // MARK: - Query Classification

    private static func isNewsQuery(_ query: String) -> Bool {
        // Whole-word match: substring `contains("now")` false-positives on "snow"/"know".
        for keyword in newsKeywords {
            if keyword.contains(" ") {
                if query.contains(keyword) { return true }
            } else {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
                if query.range(of: pattern, options: .regularExpression) != nil { return true }
            }
        }
        return false
    }

    // MARK: - SearXNG Parallel Merge

    /// Query live instances in parallel, merge results, dedup by URL.
    /// SearXNG-native freshness values match ours 1:1 (day/week/month/year).
    /// Each instance is asked for a *share* of the results (+1 slack for snippet
    /// filtering and cross-instance dedup) instead of the full count — fetching
    /// 3×maxResults to keep maxResults was pure bandwidth/latency waste.
    private func searchSearxngParallel(query: String, maxResults: Int, timeRange: String?) async -> [[String: String]] {
        let targets = Array(healthyInstances().prefix(3))
        guard !targets.isEmpty else { return [] }
        let perInstance = min(maxResults, max(2, (maxResults + targets.count - 1) / targets.count + 1))

        let allResults: [[[String: String]]] = await withTaskGroup(of: [[String: String]].self) { group in
            for instance in targets {
                group.addTask { [self] in
                    do {
                        let r = try await self.searchSearxng(query: query, maxResults: perInstance, instance: instance, timeRange: timeRange)
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

    private func searchSearxng(query: String, maxResults: Int, instance: String, timeRange: String?) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var urlString = "\(instance)/search?q=\(encoded)&format=json&categories=general&language=auto"
        if let timeRange { urlString += "&time_range=\(timeRange)" }

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Lamo/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultsArray = json["results"] as? [[String: Any]] else {
            markFailed(instance)
            throw SearchError.invalidResponse
        }

        markSuccess(instance)

        return resultsArray.prefix(maxResults).compactMap { result in
            guard let title = result["title"] as? String,
                  let url = result["url"] as? String else { return nil }
            let snippet = (result["content"] as? String) ?? ""
            // Drop results without meaningful snippets; cap the rest at the
            // source so oversized snippets never reach the context window.
            guard snippet.count >= 30 else { return nil }
            return [
                "title": SearchResultCompactor.compactTitle(title),
                "snippet": SearchResultCompactor.compactSnippet(snippet),
                "url": url.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
        }
    }

    // MARK: - Brave Search API

    private func searchBrave(query: String, maxResults: Int, apiKey: String, timeRange: String?) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // Brave freshness: pd = day, pw = week, pm = month, py = year.
        let freshnessMap = ["day": "pd", "week": "pw", "month": "pm", "year": "py"]
        var urlString = "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=\(maxResults)"
        if let timeRange, let freshness = freshnessMap[timeRange] { urlString += "&freshness=\(freshness)" }

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            throw SearchError.invalidResponse
        }

        return results.prefix(maxResults).compactMap { result in
            guard let title = result["title"] as? String,
                  let description = result["description"] as? String else { return nil }
            var item: [String: String] = [
                "title": SearchResultCompactor.compactTitle(title),
                "snippet": SearchResultCompactor.compactSnippet(description),
            ]
            if let url = result["url"] as? String {
                item["url"] = url.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return item
        }
    }

    // MARK: - DuckDuckGo HTML

    private func searchDuckDuckGoHTML(query: String, maxResults: Int, timeRange: String?) async throws -> [[String: String]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // DDG date filter: d = day, w = week, m = month, y = year.
        let dfMap = ["day": "d", "week": "w", "month": "m", "year": "y"]
        var urlString = "https://html.duckduckgo.com/html/?q=\(encoded)&kl=wt-wt"
        if let timeRange, let df = dfMap[timeRange] { urlString += "&df=\(df)" }

        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SearchError.invalidResponse
        }

        return parseDuckDuckGoResults(html: html, maxResults: maxResults)
    }

    // MARK: - DDG HTML Parsing

    private func parseDuckDuckGoResults(html: String, maxResults: Int) -> [[String: String]] {
        var results: [[String: String]] = []
        var seenURLs: Set<String> = []

        // DDG changes its markup periodically — try the known variants in order.
        let linkPatterns = [
            #"<a rel="nofollow" class="result__a" href="([^"]*)"[^>]*>(.*?)</a>"#,
            #"<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#,
        ]
        let snippetPatterns = [
            #"<a class="result__snippet"[^>]*>(.*?)</a>"#,
            #"<[^>]*class="result__snippet"[^>]*>(.*?)</a>"#,
        ]

        let linkMatches = linkPatterns.lazy.map { self.findMatches(pattern: $0, in: html) }.first { !$0.isEmpty } ?? []
        let snippetMatches = snippetPatterns.lazy.map { self.findMatches(pattern: $0, in: html) }.first { !$0.isEmpty } ?? []
        guard !linkMatches.isEmpty else { return [] }

        for (index, match) in linkMatches.enumerated() {
            guard results.count < maxResults else { break }

            guard let redirectURL = extractDuckDuckGoURL(from: match.0),
                  !seenURLs.contains(redirectURL) else { continue }

            seenURLs.insert(redirectURL)

            var result: [String: String] = [
                "title": SearchResultCompactor.compactTitle(stripHTML(match.1)),
                "url": redirectURL,
            ]

            if index < snippetMatches.count {
                let snippet = stripHTML(snippetMatches[index].1).trimmingCharacters(in: .whitespacesAndNewlines)
                if snippet.count >= 30 {
                    result["snippet"] = SearchResultCompactor.compactSnippet(snippet)
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
        let failures = (current?.failures ?? 0) + 1
        instanceHealth[instance] = (
            failures: failures,
            lastFail: Date()
        )
        // Quarantine repeat offenders so the next query doesn't wait on them again.
        // They rejoin the pool on the next periodic health check.
        if failures >= 3 {
            liveInstances.removeAll { $0 == instance }
        }
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
    case emptyQuery

    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "Invalid search URL")
        case .invalidResponse: return String(localized: "Invalid response from search engine")
        case .allProvidersFailed: return String(localized: "All search providers failed — try again later")
        case .emptyQuery: return String(localized: "Empty search query")
        }
    }
}
