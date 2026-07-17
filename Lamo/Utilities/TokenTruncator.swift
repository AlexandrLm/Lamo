import Foundation

// MARK: - Token-Aware Truncation

/// Truncates strings to a target token count using the model's real tokenizer.
/// Falls back to char/4 approximation when engine is unavailable.
enum TokenTruncator {

    /// Truncate a string to approximately `maxTokens` tokens.
    /// Uses the real tokenizer if the engine is loaded, otherwise char/4 fallback.
    /// - Parameters:
    ///   - text: The text to truncate.
    ///   - maxTokens: Target maximum token count.
    ///   - preserveSentenceBoundary: If true, tries to cut at the last sentence-ending punctuation.
    /// - Returns: Truncated string (possibly unchanged if already within limit).
    static func truncate(_ text: String, maxTokens: Int, preserveSentenceBoundary: Bool = true) async -> String {
        guard !text.isEmpty, maxTokens > 0 else { return text }

        // Fast path: if text is already short, don't bother
        let estimatedTokens = text.count / 4
        if estimatedTokens <= maxTokens { return text }

        // Get actual token count (cached)
        let actualCount = await ProviderManager.shared.tokenizeCount(text)
        if actualCount <= maxTokens { return text }

        // Binary search for the right cutoff point (tokenizer is cached, so this is fast)
        var lo = 0
        var hi = text.count
        var bestLength = 0

        while lo < hi {
            let mid = (lo + hi) / 2
            let prefix = String(text.prefix(mid))
            let tokens = await ProviderManager.shared.tokenizeCount(prefix)

            if tokens <= maxTokens {
                bestLength = mid
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        if bestLength == 0 {
            // Can't even fit maxTokens? Force-return a minimal chunk.
            return String(text.prefix(maxTokens * 3)) // Rough: 3 chars ≈ 1 token on average
        }

        var truncated = String(text.prefix(bestLength))

        // Optionally back up to the last sentence boundary
        if preserveSentenceBoundary {
            let sentenceEnders: [Character] = [".", "!", "?", "\n"]
            if let lastPunct = truncated.lastIndex(where: { sentenceEnders.contains($0) }),
               truncated.distance(from: lastPunct, to: truncated.endIndex) < bestLength / 3 {
                truncated = String(truncated[...lastPunct])
            }
        }

        return truncated + "\n\n[Truncated to \(maxTokens) tokens]"
    }

    /// Truncate a dictionary result — truncates all string values recursively.
    /// - Parameters:
    ///   - value: The result dictionary/array/string to truncate.
    ///   - maxTokens: Per-string token limit.
    /// - Returns: A new value with all string fields truncated.
    static func truncateResult(_ value: Any, maxTokens: Int) async -> Any {
        if let str = value as? String {
            return await truncate(str, maxTokens: maxTokens)
        }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (k, v) in dict {
                result[k] = await truncateResult(v, maxTokens: maxTokens)
            }
            return result
        }
        if let arr = value as? [Any] {
            var result: [Any] = []
            for v in arr {
                result.append(await truncateResult(v, maxTokens: maxTokens))
            }
            return result
        }
        return value
    }

    /// Quick estimate: tokens ≈ chars / 4. Used as fallback when engine is unavailable.
    static func fastEstimate(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}
