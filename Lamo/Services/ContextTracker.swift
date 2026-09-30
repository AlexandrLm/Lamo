import Foundation

struct ContextTracker {

    static let reservedForReply = 512

    struct MessageUsage: Identifiable {
        let id: UUID
        let role: String
        let charCount: Int
        let tokenCount: Int
        let isInContext: Bool
        let tokenOffset: Int
        let isStreaming: Bool
        let preview: String
    }

    let systemPromptTokens: Int
    let memoryTokens: Int
    let toolTokens: Int
    let toolCount: Int
    let toolCountTotal: Int
    let totalLimit: Int
    let messageUsages: [MessageUsage]
    let usedTokens: Int
    let cachedIncludedCount: Int?

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

    var reservedForReply: Int { Self.reservedForReply }

    var budgetTokens: Int { totalLimit - reservedForReply }

    var fillRatio: Double {
        guard budgetTokens > 0 else { return 0 }
        return min(Double(usedTokens) / Double(budgetTokens), 1.0)
    }

    var headroom: Int { max(budgetTokens - usedTokens, 0) }

    var hasDroppedMessages: Bool {
        messageUsages.contains { !$0.isInContext && !$0.isStreaming }
    }

    var includedCount: Int {
        cachedIncludedCount ?? messageUsages.filter { $0.isInContext && !$0.isStreaming }.count
    }

    var totalCountExcludingStreaming: Int {
        messageUsages.filter { !$0.isStreaming }.count
    }

    // MARK: - Budget Calculation (shared logic)

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

        let historyMessages = Array(messages.dropLast().reversed())
        for msg in historyMessages {
            let tokens = tokenCounts[msg.id] ?? TokenEstimation.estimateTokens(of: msg.content)
            if usedTokens + tokens > budget { continue }
            includedIDs.insert(msg.id)
            usedTokens += tokens
        }

        let dropped = messages.dropLast().filter { !includedIDs.contains($0.id) }

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

        var usagesReversed: [MessageUsage] = []
        usagesReversed.reserveCapacity(messages.count)
        var rawUsed = 0
        var cachedIncluded = 0
        var walkedTokens = 0

        for revIndex in messages.indices.reversed() {
            let msg = messages[revIndex]
            let isLast = (revIndex == messages.count - 1)
            let tokens = tokenCounts[msg.id] ?? TokenEstimation.estimateTokens(of: msg.content)
            let isInContext: Bool
            if isLast {
                isInContext = true
            } else if walkedTokens + tokens > budget {
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
