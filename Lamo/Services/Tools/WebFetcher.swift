import Foundation

// MARK: - HTML Entity Decoder

enum HTMLEntityDecoder {
    private static let entities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&#x27;", "'"), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
        ("&laquo;", "«"), ("&raquo;", "»"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
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
        text = HTMLEntityDecoder.decode(text)

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
        HTMLEntityDecoder.decode(
            html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        )
    }
}
