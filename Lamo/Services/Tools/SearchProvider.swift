import Foundation

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
        HTMLEntityDecoder.decode(
            html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
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
