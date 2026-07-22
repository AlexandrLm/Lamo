import Foundation
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
            Task { await WebFetcher.shared.enqueue(continuation) }
        }

        defer {
            Task { await WebFetcher.shared.releaseSlot() }
        }

        var lastError: Error?
        for attempt in 0..<2 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1)) }
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
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,application/pdf;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        let mimeType = (response as? HTTPURLResponse)?.mimeType ?? ""
        let isPDF = mimeType.contains("pdf") || url.pathExtension == "pdf"
        if isPDF {
            #if canImport(PDFKit)
            if let pdfText = extractPDFText(from: data) {
                let truncated = truncateContent(pdfText, maxLength: 6000)
                return PageMetadata(title: url.lastPathComponent, description: nil, contentType: "pdf", content: truncated)
            }
            #endif
            return PageMetadata(title: url.lastPathComponent, description: nil, contentType: "pdf",
                                content: "[PDF — text extraction failed: \(url.absoluteString)]")
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
                                        content: truncateContent(prettyStr, maxLength: 6000))
                }
            }
            return PageMetadata(title: url.lastPathComponent, description: nil,
                                contentType: mimeType.isEmpty ? "text" : mimeType,
                                content: truncateContent(text, maxLength: 6000))
        }

        guard let html = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .ascii) else {
            throw FetchError.invalidEncoding
        }

        let metadata = extractMetadata(from: html)
        let content = extractCleanText(from: html)

        return PageMetadata(
            title: metadata.title,
            description: metadata.description,
            contentType: metadata.contentType,
            content: truncateContent(content, maxLength: 6000)
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

    /// Remove elements that never contain useful content.
    private static func stripJunkElements(_ html: String) -> String {
        var text = html

        // Elements to remove entirely (including their content)
        let removePatterns = [
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
        ]

        for pattern in removePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }

        return text
    }

    /// Extract the main content block — article, main, or fallback to body.
    private static func extractMainContent(_ html: String) -> String {
        let contentPatterns = [
            "<article[^>]*>([\\s\\S]*?)</article>",
            "<main[^>]*>([\\s\\S]*?)</main>",
            "<div[^>]*class=[\"'][^\"']*content[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            "<div[^>]*class=[\"'][^\"']*article[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            "<div[^>]*class=[\"'][^\"']*post[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>",
            "<div[^>]*role=[\"']main[\"'][^>]*>([\\s\\S]*?)</div>",
        ]

        for pattern in contentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range),
                   match.numberOfRanges > 1,
                   let contentRange = Range(match.range(at: 1), in: html) {
                    return String(html[contentRange])
                }
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

        // Trim each line and remove very short noise lines
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "" }           // keep blank lines for paragraph breaks
            if trimmed.hasPrefix("#") { return trimmed }  // markdown headings
            if trimmed.hasPrefix("- ") { return trimmed } // list items
            if trimmed.hasPrefix("* ") { return trimmed }
            if trimmed.hasPrefix("• ") { return trimmed }
            if trimmed.count < 10 { return nil }       // drop noise fragments
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
