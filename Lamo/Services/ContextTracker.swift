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
    /// Cached included-message count (set by `build`; nil for legacy
    /// initializers — falls back to computing from `messageUsages`).
    let cachedIncludedCount: Int?

    /// Explicit initializer: a `let` with a default value is omitted from the
    /// synthesized memberwise init, so declare it here to keep the parameter.
    init(
        systemPromptTokens: Int,
        memoryTokens: Int,
        toolTokens: Int,
        toolCount: Int,
        toolCountTotal: Int,
        totalLimit: Int,
        messageUsages: [MessageUsage],
        usedTokens: Int,
        cachedIncludedCount: Int? = nil
    ) {
        self.systemPromptTokens = systemPromptTokens
        self.memoryTokens = memoryTokens
        self.toolTokens = toolTokens
        self.toolCount = toolCount
        self.toolCountTotal = toolCountTotal
        self.totalLimit = totalLimit
        self.messageUsages = messageUsages
        self.usedTokens = usedTokens
        self.cachedIncludedCount = cachedIncludedCount
    }

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
    /// O(1) when built via `build` (cached); falls back to a filtered count
    /// for trackers constructed directly (e.g. tests).
    var includedCount: Int {
        cachedIncludedCount ?? messageUsages.filter { $0.isInContext && !$0.isStreaming }.count
    }

    /// Total messages (excluding the streaming message from the "dropped" count).
    var totalCountExcludingStreaming: Int {
        messageUsages.filter { !$0.isStreaming }.count
    }

    // MARK: - Budget Calculation (shared logic)

    /// Calculate which messages fit in the KV-cache budget using real token counts.
    /// Walks messages most-recent-first, excluding the last message (sent separately).
    /// Returns included IDs, dropped messages, and whether summarization is recommended.
    ///
    /// `toolTokens` is part of the context that is sent on every turn, so it has
    /// to be charged here too — otherwise a large tool schema silently pushes
    /// the real request past the KV-cache limit.
    static func calculateBudget(
        messages: [ChatMessage],
        tokenCounts: [UUID: Int],
        systemPromptTokens: Int,
        memoryTokens: Int,
        toolTokens: Int = 0,
        maxNumTokens: Int
    ) -> (includedIDs: Set<UUID>, dropped: [ChatMessage], needsSummary: Bool, usedTokens: Int) {
        let effective = max(maxNumTokens, 512)
        let budget = max(
            0,
            effective - systemPromptTokens - memoryTokens - toolTokens - reservedForReply
        )

        var usedTokens = 0
        var includedIDs = Set<UUID>()

        // Walk most-recent-first, exclude last message (sent separately via sendMessageStream)
        let historyMessages = Array(messages.dropLast().reversed())
        for msg in historyMessages {
            let tokens = tokenCounts[msg.id] ?? TokenEstimation.estimateTokens(of: msg.content)
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
        // Same accounting as `calculateBudget`: tools are sent every turn and
        // must be charged before deciding which history still fits.
        let budget = max(
            0,
            effective - systemPromptTokens - memoryTokens - toolTokens - reservedForReply
        )

        // Single reverse walk: resolve tokens, decide inclusion (most-recent
        // wins), accumulate in-context usage, and stage usages reversed.
        // Replaces the old 4 passes (budget walk + included filter + usage
        // loop + filter/reduce for the total).
        var usagesReversed: [MessageUsage] = []
        usagesReversed.reserveCapacity(messages.count)
        var rawUsed = 0
        var cachedIncluded = 0
        var walkedTokens = 0
        // Once a message stops fitting, every older message is dropped too
        // (same break-out semantics as `calculateBudget`).
        var overBudget = false

        for revIndex in messages.indices.reversed() {
            let msg = messages[revIndex]
            let isLast = (revIndex == messages.count - 1)
            // tokenizeMessages always covers every id; the estimator is a
            // defensive fallback only — the same approximation used in every layer.
            let tokens = tokenCounts[msg.id] ?? TokenEstimation.estimateTokens(of: msg.content)
            let isInContext: Bool
            if isLast {
                isInContext = true
            } else if overBudget || walkedTokens + tokens > budget {
                overBudget = true
                isInContext = false
            } else {
                walkedTokens += tokens
                isInContext = true
            }
            if isInContext, !isLast {
                rawUsed += tokens
                cachedIncluded += 1
            }
            usagesReversed.append(MessageUsage(
                id: msg.id,
                role: msg.role == .user ? "user" : "assistant",
                charCount: msg.content.count,
                tokenCount: tokens,
                isInContext: isInContext,
                tokenOffset: 0, // fixed up forward below
                isStreaming: isLast,
                preview: String(msg.content.prefix(80))
            ))
        }

        // Restore chronological order and fill running offsets (forward fix-up,
        // no re-tokenization or filtering).
        var usages: [MessageUsage] = []
        usages.reserveCapacity(usagesReversed.count)
        var runningOffset = 0
        for usage in usagesReversed.reversed() {
            usages.append(MessageUsage(
                id: usage.id,
                role: usage.role,
                charCount: usage.charCount,
                tokenCount: usage.tokenCount,
                isInContext: usage.isInContext,
                tokenOffset: runningOffset,
                isStreaming: usage.isStreaming,
                preview: usage.preview
            ))
            if !usage.isStreaming { runningOffset += usage.tokenCount }
        }

        rawUsed += systemPromptTokens + memoryTokens + toolTokens
        // 10% safety buffer: chat template tokens, tool call formatting (injected by LiteRT-LM)
        let usedTokens = rawUsed + rawUsed / 10

        return ContextTracker(
            systemPromptTokens: systemPromptTokens,
            memoryTokens: memoryTokens,
            toolTokens: toolTokens,
            toolCount: toolCount,
            toolCountTotal: toolCountTotal,
            totalLimit: effective,
            messageUsages: usages,
            usedTokens: usedTokens,
            cachedIncludedCount: cachedIncluded
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
        toolTokens: Int = 0,
        maxNumTokens: Int,
        reservedTokens: Int = 512
    ) -> (included: [ChatMessage], dropped: [ChatMessage], needsSummary: Bool) {
        let budget = calculateBudget(
            messages: messages,
            tokenCounts: tokenCounts,
            systemPromptTokens: systemPromptTokens,
            memoryTokens: memoryTokens,
            toolTokens: toolTokens,
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
