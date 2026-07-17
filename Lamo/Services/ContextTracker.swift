import Foundation

/// Tracks how the context window is filled during a conversation.
/// Uses the model's real tokenizer for all counts — no char/4 approximation.
struct ContextTracker {

    /// Tokens reserved for the model's reply (single source of truth).
    static let reservedForReply = 512

    struct MessageUsage: Identifiable {
        let id: UUID
        let role: String          // "user" / "assistant" / "system"
        let charCount: Int
        let tokenCount: Int       // real tokenizer count
        let isInContext: Bool     // false = dropped (too old to fit in KV-cache)
        let tokenOffset: Int      // running token offset from start
        let isStreaming: Bool     // true = this message is being sent via sendMessageStream right now
        let preview: String       // first ~80 chars of message content
    }

    let systemPromptTokens: Int
    let memoryTokens: Int
    let toolTokens: Int          // tokens consumed by tool definitions
    let toolCount: Int           // how many tools were passed
    let toolCountTotal: Int      // total tools available (before filtering)
    let totalLimit: Int          // effectiveMaxTokens
    let messageUsages: [MessageUsage]
    /// Pre-computed token count — avoids O(n) filter+reduce on every read.
    let usedTokens: Int

    /// Tokens reserved for the model's reply.
    var reservedForReply: Int { Self.reservedForReply }

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

    // MARK: - Budget Calculation (shared logic)

    /// Calculate which messages fit in the KV-cache budget using real token counts.
    /// Walks messages most-recent-first, excluding the last message (sent separately).
    /// Returns included IDs, dropped messages, and whether summarization is recommended.
    static func calculateBudget(
        messages: [ChatMessage],
        tokenCounts: [UUID: Int],
        systemPromptTokens: Int,
        memoryTokens: Int,
        maxNumTokens: Int
    ) -> (includedIDs: Set<UUID>, dropped: [ChatMessage], needsSummary: Bool, usedTokens: Int) {
        let effective = max(maxNumTokens, 512)
        let budget = max(0, effective - systemPromptTokens - memoryTokens - reservedForReply)

        var usedTokens = 0
        var includedIDs = Set<UUID>()

        // Walk most-recent-first, exclude last message (sent separately via sendMessageStream)
        let historyMessages = Array(messages.dropLast().reversed())
        for msg in historyMessages {
            let tokens = tokenCounts[msg.id] ?? (msg.content.count / 4)
            if usedTokens + tokens > budget { break }
            includedIDs.insert(msg.id)
            usedTokens += tokens
        }

        let dropped = messages.dropLast().filter { !includedIDs.contains($0.id) }

        // Recommend summarization if messages were dropped OR budget is >80% full
        let needsSummary: Bool
        if !dropped.isEmpty && effective >= 1024 {
            needsSummary = true
        } else {
            let fillRatio = Double(usedTokens) / Double(max(budget, 1))
            needsSummary = fillRatio > 0.80
        }

        return (includedIDs, Array(dropped), needsSummary, usedTokens)
    }
    static func build(
        messages: [ChatMessage],
        tokenCounts: [UUID: Int],
        systemPromptTokens: Int,
        memoryTokens: Int,
        toolTokens: Int = 0,
        toolCount: Int = 0,
        toolCountTotal: Int = 0,
        maxNumTokens: Int
    ) -> ContextTracker {
        let effective = max(maxNumTokens, 512)
        let result = calculateIncluded(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: systemPromptTokens,
            memoryTokens: memoryTokens,
            maxNumTokens: maxNumTokens
        )

        let includedIDs = Set(result.included.map { $0.id })

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
                isInContext: isLast || includedIDs.contains(msg.id),
                tokenOffset: runningOffset,
                isStreaming: isLast,
                preview: String(msg.content.prefix(80))
            ))
            if !isLast { runningOffset += tokens }
        }

        let usedTokens = systemPromptTokens + memoryTokens + toolTokens + usages
            .filter { $0.isInContext && !$0.isStreaming }
            .reduce(0) { $0 + $1.tokenCount }

        return ContextTracker(
            systemPromptTokens: systemPromptTokens,
            memoryTokens: memoryTokens,
            toolTokens: toolTokens,
            toolCount: toolCount,
            toolCountTotal: toolCountTotal,
            totalLimit: effective,
            messageUsages: usages,
            usedTokens: usedTokens
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
        let budget = calculateBudget(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: systemPromptTokens,
            memoryTokens: memoryTokens,
            maxNumTokens: maxNumTokens
        )

        let included = messages.filter { budget.includedIDs.contains($0.id) }
        return (included, budget.dropped, budget.needsSummary)
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
