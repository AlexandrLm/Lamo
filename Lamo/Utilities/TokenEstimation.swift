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
    nonisolated static func estimateTokens(_ value: Any) -> Int {
        let string: String
        if let str = value as? String {
            string = str
        } else if JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value) {
            string = String(data: data, encoding: .utf8) ?? ""
        } else {
            string = String(describing: value)
        }
        return max(1, estimateTokens(of: string))
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

    nonisolated static func tokens(for text: String) -> Int {
        max(1, text.utf8.count / bytesPerToken)
    }

    nonisolated static func tokens(forTokens count: Int) -> Int { count }

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
