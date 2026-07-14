import Foundation

/// Tracks how the context window is filled during a conversation.
/// Approximates token counts (1 token ≈ 4 chars) without calling the tokenizer.
struct ContextTracker {

    struct MessageUsage: Identifiable {
        let id: UUID
        let role: String          // "user" / "assistant" / "system"
        let charCount: Int
        let tokenEstimate: Int    // charCount / 4
        let isInContext: Bool     // false = dropped (too old)
        let charOffset: Int       // running char offset from start of context
    }

    let systemPromptTokens: Int
    let memoryTokens: Int
    let totalLimit: Int          // effectiveMaxTokens
    let messageUsages: [MessageUsage]

    // MARK: - Aggregates

    /// Tokens used by system prompt + memory + history that fit.
    var usedTokens: Int {
        systemPromptTokens + memoryTokens + messageUsages.filter(\.isInContext).reduce(0) { $0 + $1.tokenEstimate }
    }

    /// Tokens reserved for the model's reply (always at least 512).
    var reservedForReply: Int { 512 }

    /// Usable budget = limit − reservedForReply.
    var budgetTokens: Int { totalLimit - reservedForReply }

    /// Percentage filled (0…1).
    var fillRatio: Double {
        guard budgetTokens > 0 else { return 0 }
        return min(Double(usedTokens) / Double(budgetTokens), 1.0)
    }

    /// Tokens still available before the model starts dropping history.
    var headroom: Int { max(budgetTokens - usedTokens, 0) }

    /// Whether any message was dropped because the budget was exceeded.
    var hasDroppedMessages: Bool { messageUsages.contains { !$0.isInContext } }

    // MARK: - Build from settings + messages

    static func build(
        messages: [ChatMessage],
        systemPrompt: String,
        memoryContext: String,
        conversationSummary: String?,
        maxNumTokens: Int,
        kvCacheAuto: Bool,
        realTokenCounts: [UUID: Int]? = nil,
        kvCacheTotalTokens: Int? = nil
    ) -> ContextTracker {
        let charLimit = 4
        let reservedTokens = 512

        let effective: Int
        if kvCacheAuto {
            effective = max(maxNumTokens, 4096)
        } else {
            effective = max(maxNumTokens, 1024)
        }

        var fullSystem = systemPrompt
        var memTokens = 0
        if MemoryService.shared.isEnabled {
            fullSystem += "\n\nRemember important user facts via update_memory tool. Summarize long conversations via summary parameter."
            if let summary = conversationSummary, !summary.isEmpty {
                fullSystem += "\n\n<conversation_summary>\n\(summary)\n</conversation_summary>"
            }
            if !memoryContext.isEmpty {
                fullSystem += "\n\n" + memoryContext
                memTokens = memoryContext.count / charLimit
            }
        }
        let sysTokens = fullSystem.count / charLimit
        let budgetChars = (effective * charLimit) - fullSystem.count - (reservedTokens * charLimit)

        var usedChars = 0
        var includedIDs = Set<UUID>()
        var offsets: [UUID: Int] = [:]
        var usages: [MessageUsage] = []
        var runningOffset = 0

        // Walk messages most-recent-first to determine which fit
        for msg in messages.dropLast().reversed() {
            let chars = msg.content.count
            if usedChars + chars > budgetChars { break }
            includedIDs.insert(msg.id)
            usedChars += chars
        }

        // Build final list in chronological order with offsets
        for msg in messages {
            let chars = msg.content.count
            usages.append(MessageUsage(
                id: msg.id,
                role: msg.role == .user ? "user" : "assistant",
                charCount: chars,
                tokenEstimate: realTokenCounts?[msg.id] ?? (chars / charLimit),
                isInContext: includedIDs.contains(msg.id),
                charOffset: runningOffset
            ))
            runningOffset += chars
        }

        return ContextTracker(
            systemPromptTokens: sysTokens,
            memoryTokens: memTokens,
            totalLimit: effective,
            messageUsages: usages
        )
    }

    // MARK: - Formatting

    /// Format token count: "256", "1.2K", "14K"
    static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1000 {
            let k = Double(tokens) / 1000
            return k == Double(Int(k)) ? "\(Int(k))K" : String(format: "%.1fK", k)
        }
        return "\(tokens)"
    }
}