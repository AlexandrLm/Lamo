import Foundation

// MARK: - Token Estimation (single source of truth)

///
/// Central token estimator used by every layer that lacks the real tokenizer:
/// `AgenticLoopBudget`, `SearchResultCompactor`, `TokenTruncator` fallbacks,
/// `ContextTracker`/`TokenBudget` fallbacks, and provider benchmark reporting.
///
/// Formula (conservative for non-ASCII): ASCII ≈ 4 chars/token, non-ASCII
/// (Cyrillic, CJK, …) ≈ 1 char/token. Over-estimating is safe — budgets stop
/// slightly early rather than overflowing the KV cache.
enum TokenEstimation {
    /// Rough token estimate for an arbitrary tool-result value.
    /// Uses `estimatedSize` (structural walk, no JSONSerialization) for
    /// non-string values; strings go through the single-source formula.
    nonisolated static func estimateTokens(_ value: Any) -> Int {
        if let str = value as? String {
            return estimateTokens(of: str)
        }
        return max(1, estimatedSize(value) / bytesPerToken)
    }

    /// Rough token estimate for a string.
    nonisolated static func estimateTokens(of string: String) -> Int {
        var ascii = 0
        var nonAscii = 0
        for scalar in string.unicodeScalars {
            if scalar.isASCII { ascii += 1 } else { nonAscii += 1 }
        }
        return max(1, ascii / 4 + nonAscii)
    }

    /// Char-based fallback when the real tokenizer is unavailable.
    /// Single entry point used by TokenBudget, ContextTracker and
    /// ConversationBuilder so every layer agrees on the estimate.
    nonisolated static func fallback(_ string: String) -> Int {
        estimateTokens(of: string)
    }

    // MARK: - UTF-8 budgets (used by TokenTruncator)

    /// Bytes per token heuristic.
    nonisolated static let bytesPerToken = 4

    /// UTF-8-bytes based estimate — alias of the single-source formula.
    /// Kept for callers that think in bytes; delegates to `estimateTokens(of:)`
    /// so every layer agrees on the estimate.
    nonisolated static func tokens(for text: String) -> Int {
        estimateTokens(of: text)
    }

    /// Char budget corresponding to a token budget.
    nonisolated static func charBudget(forTokens maxTokens: Int) -> Int {
        max(400, maxTokens * bytesPerToken)
    }

    /// Byte budget corresponding to a token budget.
    nonisolated static func byteBudget(forTokens maxTokens: Int) -> Int {
        charBudget(forTokens: maxTokens)
    }

    /// Estimated serialized size of an arbitrary JSON-ish value without
    /// running `JSONSerialization` — walks the structure summing UTF-8 bytes.
    nonisolated static func estimatedSize(_ value: Any) -> Int {
        switch value {
        case let s as String:
            return s.utf8.count
        case let dict as [String: Any]:
            var total = 2 // braces
            for (k, v) in dict {
                total += k.utf8.count + 3 + estimatedSize(v) + 1
            }
            return total
        case let arr as [Any]:
            var total = 2 // brackets
            for item in arr { total += estimatedSize(item) + 1 }
            return total
        case is Int, is Double, is Bool:
            return 8
        case is NSNull:
            return 4
        default:
            return String(describing: value).utf8.count
        }
    }
}
