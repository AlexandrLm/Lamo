import Foundation

// MARK: - Agentic Loop Budget

/// Manages token budget across tool calls in an agentic loop to prevent KV-cache overflow.
///
/// Strategy: each tool call consumes one iteration. The budget is divided evenly
/// among remaining iterations. Tool results are truncated to their per-iteration limit.
///
///     Total budget: 9000 tokens (example)
///     ├── System overhead: ~2000 (prompt + memory + tool defs)
///     ├── Conversation skeleton: ~1500 (last user turns)
///     ├── Working budget: ~5500
///     │   └── Per-iteration: ~1100 (divided evenly, 5 max iterations)
///     └── Reserve for final reply: 512
actor AgenticLoopBudget {
    static let shared = AgenticLoopBudget()

    /// Token budget reserved for the final model response.
    static let reservedForReply = 512

    /// Default max iterations — hard cap to prevent infinite loops.
    static let defaultMaxIterations = 5

    /// Minimum tokens to keep per tool result (never truncate below this).
    static let minToolResultTokens = 150

    // MARK: - State

    private var totalBudget: Int = 4096
    private var systemOverhead: Int = 0
    private var conversationSkeletonTokens: Int = 0
    private var maxIterations: Int = defaultMaxIterations

    private var tokensUsed: Int = 0
    private var iterationCount: Int = 0

    /// Whether the loop is currently active.
    private(set) var isActive: Bool = false

    // MARK: - Configuration

    /// Configure the budget for a new agentic loop (one per user message).
    func configure(
        totalBudget: Int,
        systemOverhead: Int,
        conversationSkeletonTokens: Int,
        maxIterations: Int = defaultMaxIterations
    ) {
        self.totalBudget = totalBudget
        self.systemOverhead = systemOverhead
        self.conversationSkeletonTokens = conversationSkeletonTokens
        self.maxIterations = maxIterations
        self.tokensUsed = 0
        self.iterationCount = 0
        self.isActive = true
    }

    /// Reset budget for a new conversation turn.
    func reset() {
        isActive = false
        tokensUsed = 0
        iterationCount = 0
    }

    // MARK: - Budget Queries

    /// Total working budget = totalBudget - overhead - skeleton - reserve.
    var workingBudget: Int {
        max(0, totalBudget - systemOverhead - conversationSkeletonTokens - Self.reservedForReply)
    }

    /// Whether the loop should stop (budget exhausted or iteration cap hit).
    var shouldStop: Bool {
        iterationCount >= maxIterations || tokensUsed >= workingBudget
    }

    /// Remaining headroom in tokens.
    var headroom: Int {
        max(0, workingBudget - tokensUsed)
    }

    // MARK: - Iteration Tracking

    /// Call at the START of each tool's run() to consume one iteration.
    /// Returns the max tokens allowed for this tool's result (min 150, max 1500).
    /// Returns 2000 if the budget is inactive (normal chat, not agentic loop).
    func consumeIteration() -> Int {
        guard isActive else { return 2000 }

        if iterationCount >= maxIterations {
            return Self.minToolResultTokens
        }

        iterationCount += 1
        let remaining = workingBudget - tokensUsed
        let remainingIterations = max(maxIterations - iterationCount + 1, 1)
        let perIteration = remaining / remainingIterations
        let limit = max(perIteration / 2, Self.minToolResultTokens)
        return min(limit, 1500)
    }

    /// Record the actual token cost of a tool result after truncation.
    func recordCost(tokens: Int) {
        tokensUsed += tokens
    }

    /// Get the current iteration number (1-based, for display).
    var currentIteration: Int { iterationCount }

    /// Total iterations consumed so far.
    var totalIterations: Int { iterationCount }
}
