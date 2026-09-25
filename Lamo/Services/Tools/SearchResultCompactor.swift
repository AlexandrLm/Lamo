import Foundation

// MARK: - Search Result Compactor

/// Domain-aware compaction for web-search output.
///
/// Problem: the generic `TokenTruncator` cuts blindly — it can chop URLs (the model's
/// only pointers to full pages) or halve the result list mid-way. This compactor runs
/// *before* the generic pass and guarantees fit while keeping structure intact:
/// URLs and titles are never touched; auto-fetched `content` shrinks first, then
/// snippets, and only last are trailing results dropped — with an explicit marker.
enum SearchResultCompactor {
    /// Snippets longer than this are cut at a sentence/word boundary (at the source).
    nonisolated static let maxSnippetChars = 300
    /// Titles longer than this are cut at a word boundary.
    nonisolated static let maxTitleChars = 150
    /// Snippets are never shrunk below this during budget fitting.
    nonisolated static let minSnippetChars = 80
    /// Auto-fetched excerpts shrink first; shorter ones are removed instead of kept.
    nonisolated static let minContentChars = 200
    /// Queries longer than this are prefix-cut (models sometimes paste full sentences).
    nonisolated static let maxQueryChars = 200

    // MARK: - Query

    /// Trim, collapse all whitespace runs to single spaces, cap length.
    nonisolated static func sanitizeQuery(_ query: String) -> String {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        q = q.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if q.count > maxQueryChars {
            q = String(q.prefix(maxQueryChars))
        }
        return q.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func cacheKey(query: String, timeRange: String?) -> String {
        let q = sanitizeQuery(query).lowercased()
        if let r = timeRange { return "\(q)|\(r)" }
        return q
    }

    // MARK: - Field compaction

    nonisolated static func compactSnippet(_ snippet: String) -> String {
        cutAtBoundary(snippet, maxChars: maxSnippetChars)
    }

    nonisolated static func compactTitle(_ title: String) -> String {
        cutAtBoundary(title, maxChars: maxTitleChars)
    }

    /// Cut text to `maxChars`, preferring a sentence end, then a word break.
    /// Sentence cuts keep their trailing punctuation; mid-sentence cuts get "…".
    nonisolated static func cutAtBoundary(_ text: String, maxChars: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxChars, maxChars > 0 else { return t }
        let head = String(t.prefix(maxChars))
        let floor = max(1, maxChars / 2)
        // 1. Sentence end: last `.`/`!`/`?`/newline, kept only if past the floor
        //    (a cut at char 5 of 300 would throw away too much — fall through).
        if let idx = head.lastIndex(where: { ".!?\n".contains($0) }),
           head.distance(from: head.startIndex, to: idx) >= floor {
            if head[idx] == "\n" {
                return String(head[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(head[...idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 2. Word break.
        if let space = head.lastIndex(of: " "),
           head.distance(from: head.startIndex, to: space) >= floor {
            return String(head[..<space]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        // 3. Hard cut (single long token, e.g. a URL pasted into text).
        return head.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // MARK: - Token estimate

    /// Same formula as `AgenticLoopBudget.estimateTokens(of:)` — keep in sync.
    /// ASCII ≈ 4 chars/token, non-ASCII (Cyrillic, CJK, …) ≈ 1 char/token.
    nonisolated static func estimateTokens(of string: String) -> Int {
        var ascii = 0
        var nonAscii = 0
        for scalar in string.unicodeScalars {
            if scalar.isASCII { ascii += 1 } else { nonAscii += 1 }
        }
        return max(1, ascii / 4 + nonAscii)
    }

    nonisolated static func estimateTokens(ofResults results: [[String: Any]]) -> Int {
        guard JSONSerialization.isValidJSONObject(results),
              let data = try? JSONSerialization.data(withJSONObject: results),
              let str = String(data: data, encoding: .utf8) else {
            return results.reduce(0) { $0 + estimateTokens(of: "\($1)") }
        }
        return estimateTokens(of: str)
    }

    // MARK: - Budget fitting

    /// Shrink search results to a token budget. `url`/`title` are never touched;
    /// `content` (auto-fetch) shrinks first, then `snippet`, and only last are
    /// trailing results dropped — with a "+N more omitted" marker on the survivor.
    nonisolated static func fitResults(_ results: [[String: Any]], tokenLimit: Int) -> [[String: Any]] {
        guard tokenLimit > 0, !results.isEmpty else { return results }
        var fitted = results
        var dropped = 0
        var rounds = 0
        while estimateTokens(ofResults: fitted) > tokenLimit, rounds < 50 {
            rounds += 1
            if shrinkLongestContent(&fitted) { continue }
            if shrinkLongestSnippet(&fitted) { continue }
            guard fitted.count > 1 else { break }
            fitted.removeLast()
            dropped += 1
        }
        if dropped > 0, !fitted.isEmpty {
            var last = fitted[fitted.count - 1]
            let snippet = last["snippet"] as? String ?? ""
            last["snippet"] = snippet + " …[+\(dropped) more omitted]"
            fitted[fitted.count - 1] = last
        }
        return fitted
    }

    /// Halve the longest `content` field (or drop it when already short).
    /// Returns true only when the payload actually got smaller — a no-op cut
    /// (e.g. spaceless text where the "…" re-adds the saved char) reports false
    /// so the fitter moves on to dropping trailing results instead of spinning.
    nonisolated private static func shrinkLongestContent(_ results: inout [[String: Any]]) -> Bool {
        var bestIdx: Int?
        var bestLen = 0
        for (i, item) in results.enumerated() {
            if let content = item["content"] as? String, !content.isEmpty, content.count > bestLen {
                bestIdx = i
                bestLen = content.count
            }
        }
        guard let idx = bestIdx, var item = results[safe: idx] else { return false }
        if bestLen > minContentChars * 2 {
            let content = item["content"] as? String ?? ""
            let cut = cutAtBoundary(content, maxChars: bestLen / 2)
            guard cut.count < bestLen else { return false }
            item["content"] = cut
        } else {
            // Too short to halve meaningfully — drop the field, keep the snippet.
            item.removeValue(forKey: "content")
        }
        results[idx] = item
        return true
    }

    /// Halve the longest `snippet` above the minimum. Never removes snippets.
    /// Returns false when nothing can shrink further (all at the minimum or cuts
    /// are no-ops), letting the fitter drop trailing results instead of spinning.
    nonisolated private static func shrinkLongestSnippet(_ results: inout [[String: Any]]) -> Bool {
        var bestIdx: Int?
        var bestLen = 0
        for (i, item) in results.enumerated() {
            if let snippet = item["snippet"] as? String,
               snippet.count > minSnippetChars, snippet.count > bestLen {
                bestIdx = i
                bestLen = snippet.count
            }
        }
        guard let idx = bestIdx, var item = results[safe: idx] else { return false }
        let snippet = item["snippet"] as? String ?? ""
        let target = max(minSnippetChars, bestLen / 2)
        // A cut that doesn't shorten (spaceless text + "…" marker) is not progress.
        guard target < bestLen else { return false }
        let cut = cutAtBoundary(snippet, maxChars: target)
        guard cut.count < bestLen else { return false }
        item["snippet"] = cut
        results[idx] = item
        return true
    }
}

// MARK: - Safe index

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
