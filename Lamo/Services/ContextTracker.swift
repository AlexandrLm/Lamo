import Foundation

/// Tracks how the context window is filled during a conversation.
/// Uses the model's real tokenizer for all counts — no char/4 approximation.
struct ContextTracker {

    struct MessageUsage: Identifiable {
        let id: UUID
        let role: String          // "user" / "assistant" / "system"
        let charCount: Int
        let tokenCount: Int       // real tokenizer count
        let isInContext: Bool     // false = dropped (too old to fit in KV-cache)
        let tokenOffset: Int      // running token offset from start
        let isStreaming: Bool     // true = this message is being sent via sendMessageStream right now
    }

    let systemPromptTokens: Int
    let memoryTokens: Int
    let totalLimit: Int          // effectiveMaxTokens
    let messageUsages: [MessageUsage]

    // MARK: - Aggregates

    /// Tokens used by system prompt + memory + history that fit in the KV-cache.
    /// Excludes the streaming message (it's being sent now, not yet in cache).
    var usedTokens: Int {
        systemPromptTokens + memoryTokens + messageUsages.filter { $0.isInContext && !$0.isStreaming }.reduce(0) { $0 + $1.tokenCount }
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
    /// Excludes the "streaming" message (last message sent via sendMessageStream — not a real drop).
    var hasDroppedMessages: Bool {
        messageUsages.contains { !$0.isInContext && !$0.isStreaming }
    }

    /// Number of messages that fit in the KV-cache (excluding the streaming message).
    var includedCount: Int {
        messageUsages.filter { $0.isInContext && !$0.isStreaming }.count
    }

    /// Total messages (excluding the streaming message from the "dropped" count).
    var totalCountExcludingStreaming: Int {
        messageUsages.filter { !$0.isStreaming }.count
    }

    // MARK: - Build from settings + messages (requires real token counts)

    /// - Parameters:
    ///   - messages: All messages in the conversation.
    ///   - tokenCounts: Real token counts per message ID (from engine.tokenize).
    ///   - systemPromptTokens: Real token count of the system prompt.
    ///   - memoryTokens: Real token count of the memory context.
    ///   - maxNumTokens: Configured KV-cache budget (real value from safeMaxTokens, not UserDefaults).
    static func build(
        messages: [ChatMessage],
        tokenCounts: [UUID: Int],
        systemPromptTokens: Int,
        memoryTokens: Int,
        maxNumTokens: Int
    ) -> ContextTracker {
        let reservedTokens = 512

        // Use the real KV-cache budget from ProviderManager (passed as maxNumTokens).
        // Minimum 512 tokens to ensure meaningful tracking even on low-memory devices.
        let effective = max(maxNumTokens, 512)

        let budget = effective - systemPromptTokens - memoryTokens - reservedTokens

        // Walk messages most-recent-first to determine which fit by token count.
        // Exclude the last message — it's sent via sendMessageStream and is always "in context".
        let historyMessages = Array(messages.dropLast())
        var usedTokens = 0
        var includedIDs = Set<UUID>()
        for msg in historyMessages.reversed() {
            let tokens = tokenCounts[msg.id] ?? 0
            if usedTokens + tokens > budget { break }
            includedIDs.insert(msg.id)
            usedTokens += tokens
        }

        // Build final list in chronological order
        var usages: [MessageUsage] = []
        var runningOffset = 0
        for (index, msg) in messages.enumerated() {
            let tokens = tokenCounts[msg.id] ?? 0
            let isLast = (index == messages.count - 1)
            usages.append(MessageUsage(
                id: msg.id,
                role: msg.role == .user ? "user" : "assistant",
                charCount: msg.content.count,
                tokenCount: tokens,
                // Last message is always "in context" — it's sent via sendMessageStream.
                // Other messages are in context only if they fit in the KV-cache budget.
                isInContext: isLast || includedIDs.contains(msg.id),
                tokenOffset: runningOffset,
                isStreaming: isLast
            ))
            if !isLast { runningOffset += tokens }
        }

        return ContextTracker(
            systemPromptTokens: systemPromptTokens,
            memoryTokens: memoryTokens,
            totalLimit: effective,
            messageUsages: usages
        )
    }

    // MARK: - Budget calculation for buildConversation

    /// Calculate which messages fit in the KV-cache budget using real token counts.
    /// Returns the included messages (excluding the last user message) and whether
    /// summarization is recommended.
    static func calculateIncluded(
        messages: [ChatMessage],
        tokenCounts: [UUID: Int],
        systemPromptTokens: Int,
        memoryTokens: Int,
        maxNumTokens: Int,
        reservedTokens: Int = 512
    ) -> (included: [ChatMessage], dropped: [ChatMessage], needsSummary: Bool) {
        let effective = max(maxNumTokens, 512)
        let budget = max(0, effective - systemPromptTokens - memoryTokens - reservedTokens)

        var usedTokens = 0
        var includedIDs = [UUID]()

        // Walk most-recent-first, exclude last message (sent separately via sendMessageStream)
        let historyMessages = Array(messages.dropLast().reversed())
        for msg in historyMessages {
            let tokens = tokenCounts[msg.id] ?? (msg.content.count / 4)
            if usedTokens + tokens > budget { break }
            includedIDs.insert(msg.id, at: 0)
            usedTokens += tokens
        }

        let includedSet = Set(includedIDs)
        let included = messages.filter { includedSet.contains($0.id) }
        let dropped = messages.dropLast().filter { !includedSet.contains($0.id) }

        // Recommend summarization only if messages were actually dropped (not just the last one)
        // AND the budget is large enough to warrant a summary
        let needsSummary: Bool
        if !dropped.isEmpty && effective >= 1024 {
            needsSummary = true
        } else {
            let fillRatio = Double(usedTokens) / Double(max(budget, 1))
            needsSummary = fillRatio > 0.80
        }

        return (included, Array(dropped), needsSummary)
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
