import Foundation
import os
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Web Fetcher

/// Fetches URLs and extracts clean, readable text content for LLM consumption.
///
/// Cleaning pipeline (in order):
/// 1. Strip non-content elements: nav, footer, header, sidebar, ads, cookie banners
/// 2. Extract main content block (article/main/content div)
/// 3. Remove inline junk: scripts, styles, trackers, social widgets
/// 4. Normalize whitespace preserving paragraph breaks
/// 5. Truncate at sentence boundary near maxLength
actor WebFetcher {
    static let shared = WebFetcher()
    // MARK: - Shared State (lock-protected; static on actor = not actor-isolated)

    private static let stateLock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var activeTasks = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
        var inFlight: [String: Task<PageMetadata, Error>] = [:]
    }

    private final class CacheEntry: NSObject {
        let content: String
        let timestamp: Date
        init(content: String, timestamp: Date) { self.content = content; self.timestamp = timestamp }
    }
    private static let contentCache: NSCache<NSString, CacheEntry> = {
        let c = NSCache<NSString, CacheEntry>()
        c.countLimit = 100
        c.totalCostLimit = 10 * 1024 * 1024
        return c
    }()

    private static let maxConcurrent = 3
    private static let contentCacheTTL: TimeInterval = 1800 // 30 min
    private static let maxDownloadBytes = 2_000_000 // 2 MB — refuse huge files before parsing

    /// Ephemeral session: no shared cookies/credential store, bounded timeouts.
    private static let session: URLSession = SecureURLPolicy.makeSession()

    /// Fetch a URL and return plain text content.
    static func fetch(url: URL) async throws -> String {
        let result = try await fetchStructured(url: url)
        return result.content
    }

    /// Fetch a URL and return structured metadata + content.
    /// Single cache (NSCache, TTL-checked); concurrent callers for the same URL
    /// share one in-flight Task instead of double-fetching.
    static func fetchStructured(url: URL) async throws -> PageMetadata {
        let cacheKey = url.absoluteString
        if let cached = contentCache.object(forKey: cacheKey as NSString),
           Date().timeIntervalSince(cached.timestamp) < contentCacheTTL {
            return PageMetadata(title: nil, description: nil, contentType: nil, content: cached.content, finalURL: url)
        }
        // In-flight dedup: join the existing task if present.
        if let existing = stateLock.withLock({ $0.inFlight[cacheKey] }) {
            return try await existing.value
        }
        let task = Task<PageMetadata, Error> {
            defer { stateLock.withLock { $0.inFlight.removeValue(forKey: cacheKey) } }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Task { await WebFetcher.shared.enqueue(continuation) }
            }
            defer { Task { await WebFetcher.shared.releaseSlot() } }
            let result = try await fetchWithRetry(url: url)
            contentCache.setObject(
                CacheEntry(content: result.content, timestamp: Date()),
                forKey: cacheKey as NSString,
                cost: result.content.utf8.count
            )
            return result
        }
        stateLock.withLock { $0.inFlight[cacheKey] = task }
        return try await task.value
    }

    /// Retry only transient failures (5xx/429/network), with jitter. Never retries CancellationError.
    private static func fetchWithRetry(url: URL) async throws -> PageMetadata {
        var lastError: Error?
        for attempt in 0..<2 {
            if attempt > 0 {
                let jitter = Double.random(in: 0.5...1.5)
                try await Task.sleep(for: .seconds(1 * jitter))
            }
            do {
                return try await fetchOnceStructured(url: url)
            } catch is CancellationError {
                throw CancellationError()
            } catch let fetchError as FetchError {
                lastError = fetchError
                if !fetchError.isTransient { break }
            } catch let urlError as URLError {
                lastError = urlError
                if !isTransientURLError(urlError) { break }
            } catch {
                lastError = error
                break
            }
        }
        throw lastError ?? FetchError.invalidEncoding
    }

    private static func isTransientURLError(_ e: URLError) -> Bool {
        switch e.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private func enqueue(_ continuation: CheckedContinuation<Void, Never>) {
        Self.stateLock.withLock { state in
            if state.activeTasks < Self.maxConcurrent {
                state.activeTasks += 1
                continuation.resume()
            } else {
                state.waiters.append(continuation)
            }
        }
    }

    private func releaseSlot() {
        Self.stateLock.withLock { state in
            state.activeTasks -= 1
            if !state.waiters.isEmpty {
                state.activeTasks += 1
                state.waiters.removeFirst().resume()
            }
        }
    }

    private static func fetchOnceStructured(url: URL) async throws -> PageMetadata {
        // Defence in depth: the tool validates first, but every fetch goes
        // through here, so this is the last place a private address can slip in.
        try SecureURLPolicy.validate(url)

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,application/pdf;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = SecureURLPolicy.requestTimeout

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FetchError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard data.count <= maxDownloadBytes else {
            throw FetchError.tooLarge(data.count)
        }
        // URLSession follows redirects transparently; re-validate the hop we
        // actually landed on.
        let finalURL = http.url ?? url
        try SecureURLPolicy.validate(finalURL)

        let mimeType = http.mimeType ?? ""
        let isPDF = mimeType.contains("pdf") || url.pathExtension == "pdf"
        if isPDF {
            #if canImport(PDFKit)
            if let pdfText = extractPDFText(from: data) {
                let truncated = truncateContent(pdfText, maxLength: 4000)
                return PageMetadata(title: url.lastPathComponent, description: nil, contentType: "pdf",
                                    content: truncated, finalURL: finalURL)
            }
            #endif
            return PageMetadata(title: url.lastPathComponent, description: nil, contentType: "pdf",
                                content: String(localized: "[PDF — text extraction failed: \(url.absoluteString)]"),
                                finalURL: finalURL)
        }

        // Plain text, JSON, XML — return as-is
        let isPlainText = mimeType.hasPrefix("text/plain")
        let isJSON = mimeType.contains("json") || url.pathExtension == "json"
        let isXML = mimeType.contains("xml") || url.pathExtension == "xml"
        if isPlainText || isJSON || isXML {
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
            if isJSON {
                if let obj = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
                   let prettyStr = String(data: pretty, encoding: .utf8) {
                    return PageMetadata(title: url.lastPathComponent, description: nil, contentType: "json",
                                        content: truncateContent(prettyStr, maxLength: 4000), finalURL: finalURL)
                }
            }
            return PageMetadata(title: url.lastPathComponent, description: nil,
                                contentType: mimeType.isEmpty ? "text" : mimeType,
                                content: truncateContent(text, maxLength: 4000), finalURL: finalURL)
        }

        guard let html = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .ascii) else {
            throw FetchError.invalidEncoding
        }

        // Heavy string parsing runs detached (outside actor isolation, background QoS).
        let parsed: (RawMetadata, String) = await Task.detached(priority: .utility) {
            let metadata = WebFetcher.extractMetadata(from: html)
            let content = WebFetcher.extractCleanText(from: html)
            return (metadata, content)
        }.value
        let metadata = parsed.0
        let content = parsed.1

        return PageMetadata(
            title: metadata.title,
            description: metadata.description,
            contentType: metadata.contentType,
            content: truncateContent(content, maxLength: 4000),
            finalURL: finalURL
        )
    }

    // MARK: - HTML Cleaning Pipeline

    /// Full pipeline: strip junk → extract main content → normalize → truncate.
    private static func extractCleanText(from html: String) -> String {
        var text = html

        // Phase 1: Remove non-content elements completely
        text = stripJunkElements(text)

        // Phase 2: Try to extract the main content block
        text = extractMainContent(text)

        // Phase 3: Strip remaining tags and clean up
        text = normalizeText(text)

        return text
    }

    /// Precompiled junk-element patterns — built once instead of on every fetch.
    private static let junkRegexes: [NSRegularExpression] = [
        "<script[^>]*>[\\s\\S]*?</script>",
        "<style[^>]*>[\\s\\S]*?</style>",
        "<noscript[^>]*>[\\s\\S]*?</noscript>",
        "<iframe[^>]*>[\\s\\S]*?</iframe>",
        "<svg[^>]*>[\\s\\S]*?</svg>",
        "<nav[^>]*>[\\s\\S]*?</nav>",
        "<footer[^>]*>[\\s\\S]*?</footer>",
        "<header[^>]*>[\\s\\S]*?</header>",
        // Cookie/GDPR banners
        "<div[^>]*id=[\"'](?:cookie|gdpr|consent)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>",
        "<div[^>]*class=[\"'][^\"']*(?:cookie|gdpr|consent|banner)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>",
        // Ads and trackers
        "<div[^>]*id=[\"'](?:ad|ads|advert)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>",
        "<div[^>]*class=[\"'][^\"']*(?:ad|ads|advert|sponsor|tracking)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>",
        // Social sharing widgets
        "<div[^>]*class=[\"'][^\"']*(?:share|social|comment)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>",
        // Sidebar
        "<aside[^>]*>[\\s\\S]*?</aside>",
        "<div[^>]*id=[\"']sidebar[\"'][^>]*>[\\s\\S]*?</div>",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .dotMatchesLineSeparators]) }

    /// Remove elements that never contain useful content.
    private static func stripJunkElements(_ html: String) -> String {
        var text = html
        for regex in junkRegexes {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return text
    }

    /// Precompiled main-content patterns — built once.
    private static let contentRegexes: [NSRegularExpression] = [
        "<article[^>]*>([\\s\\S]*?)</article>",
        "<main[^>]*>([\\s\\S]*?)</main>",
        "<div[^>]*role=[\"']main[\"'][^>]*>([\\s\\S]*?)</div>",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .dotMatchesLineSeparators]) }

    /// Extract the main content block — article, main, or fallback to full HTML.
    /// NOTE: class-based div heuristics (`content`/`article`/`post`) intentionally omitted:
    /// non-greedy `[\s\S]*?` stops at the first nested `</div>` and truncates real articles.
    private static func extractMainContent(_ html: String) -> String {
        for regex in contentRegexes {
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               match.numberOfRanges > 1,
               let contentRange = Range(match.range(at: 1), in: html) {
                return String(html[contentRange])
            }
        }
        return html
    }

    /// Final normalization: strip tags, decode entities, collapse whitespace.
    private static func normalizeText(_ text: String) -> String {
        var result = text

        // Strip remaining HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        result = HTMLEntityDecoder.decode(result)

        // Collapse runs of whitespace within lines
        result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

        // Collapse 3+ newlines to 2
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        // Trim each line, dropping only clear noise (not short facts like "Yes"/"42°C").
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "" }           // keep blank lines for paragraph breaks
            if trimmed.hasPrefix("#") { return trimmed }  // markdown headings
            if trimmed.hasPrefix("- ") { return trimmed } // list items
            if trimmed.hasPrefix("* ") { return trimmed }
            if trimmed.hasPrefix("• ") { return trimmed }
            // Keep short lines that carry signal (numbers, units, yes/no).
            if trimmed.count < 4 {
                let hasAlnum = trimmed.rangeOfCharacter(from: .alphanumerics) != nil
                return hasAlnum ? trimmed : nil
            }
            return trimmed
        }

        result = cleaned.joined(separator: "\n")

        // Final whitespace collapse
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Truncates content at sentence boundary near maxLength.
    private static func truncateContent(_ content: String, maxLength: Int) -> String {
        guard content.count > maxLength else { return content }
        let truncated = String(content.prefix(maxLength))
        // Try to break at sentence end
        for sep in [". ", ".\n", "! ", "?\n", "? ", "!\n"] {
            if let range = truncated.range(of: sep, options: .backwards) {
                return String(truncated[...range.lowerBound]) + "."
            }
        }
        // Fallback: break at last newline
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[...lastNewline])
        }
        return truncated
    }

    // MARK: - Metadata Extraction

    private struct RawMetadata {
        var title: String?
        var description: String?
        var contentType: String?
    }

    private static func extractMetadata(from html: String) -> RawMetadata {
        var meta = RawMetadata()

        // <title>
        if let titleRange = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: .regularExpression) {
            let titleHTML = String(html[titleRange])
            meta.title = stripTags(titleHTML).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        meta.description = extractMetaContent(from: html, property: "og:description")
            ?? extractMetaContent(from: html, property: "description")

        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            meta.title = ogTitle
        }

        if let ogType = extractMetaContent(from: html, property: "og:type") {
            meta.contentType = ogType
        } else if html.contains("<article") {
            meta.contentType = "article"
        }

        return meta
    }

    private static func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]*property=\"\(property)\"[^>]*content=\"([^\"]*)\"",
            "<meta[^>]*content=\"([^\"]*)\"[^>]*property=\"\(property)\"",
            "<meta[^>]*name=\"\(property)\"[^>]*content=\"([^\"]*)\"",
            "<meta[^>]*content=\"([^\"]*)\"[^>]*name=\"\(property)\"",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range),
                   match.numberOfRanges > 2,
                   let contentRange = Range(match.range(at: 2), in: html) {
                    let value = String(html[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    private static func stripTags(_ html: String) -> String {
        HTMLEntityDecoder.decode(
            html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        )
    }

    // MARK: - PDF

    #if canImport(PDFKit)
    private static func extractPDFText(from data: Data) -> String? {
        guard let pdf = PDFDocument(data: data) else { return nil }
        let pages = (0..<pdf.pageCount).compactMap { i -> String? in
            pdf.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !pages.isEmpty else { return nil }
        return pages.joined(separator: "\n\n")
    }
    #endif
}

// MARK: - Types

struct PageMetadata {
    let title: String?
    let description: String?
    let contentType: String?
    let content: String
    /// Where the request ended up after redirects — re-validated by the caller
    /// so a redirect cannot walk into the local network.
    let finalURL: URL?

    init(title: String?, description: String?, contentType: String?, content: String, finalURL: URL? = nil) {
        self.title = title
        self.description = description
        self.contentType = contentType
        self.content = content
        self.finalURL = finalURL
    }
}

enum FetchError: LocalizedError {
    case invalidURL
    case invalidEncoding
    case badStatus(Int)
    case tooLarge(Int)

    /// Only 5xx and rate-limit 429 deserve a retry; 4xx/too-large never succeed on retry.
    var isTransient: Bool {
        switch self {
        case .badStatus(let code): return code == 429 || (500...599).contains(code)
        case .invalidEncoding, .tooLarge, .invalidURL: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "Invalid URL")
        case .invalidEncoding: return String(localized: "Could not decode response")
        case .badStatus(let code): return String(localized: "Server returned status \(code)")
        case .tooLarge(let bytes): return String(localized: "Page too large (\(bytes) bytes, limit 2 MB)")
        }
    }
}

// MARK: - HTML Entity Decoder

enum HTMLEntityDecoder {
    private nonisolated static let entities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&#x27;", "'"), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
        ("&laquo;", "«"), ("&raquo;", "»"),
        ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
        ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"),
    ]

    nonisolated static func decode(_ text: String) -> String {
        var result = text
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities
        if let entityRegex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = entityRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let numRange = Range(match.range(at: 1), in: result),
                      let codePoint = UInt32(String(result[numRange])),
                      let scalar = Unicode.Scalar(codePoint),
                      let fullRange = Range(match.range, in: result) else { continue }
                result.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }
        return result
    }
}
