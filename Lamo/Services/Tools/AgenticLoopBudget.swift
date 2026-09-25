import Foundation

// MARK: - Agentic Loop Budget

/// Manages token budget across tool calls in an agentic loop to prevent KV-cache overflow.
///
/// Strategy: every tool execution consumes one iteration. The budget is divided evenly
/// among remaining iterations. Tool results are truncated to their per-iteration limit.
/// Iterations are granted in `softStopNotice()` (the first thing every tool calls), so
/// failing tools also count — a model stuck in an error loop is stopped by the same cap.
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

    /// Maximum tokens granted for a single tool result.
    static let maxToolResultTokens = 1500

    /// Grants when the budget is inactive (normal chat, not agentic loop).
    private static let inactiveLimit = 2000

    // MARK: - State

    private var totalBudget: Int = 4096
    private var systemOverhead: Int = 0
    private var conversationSkeletonTokens: Int = 0
    private var maxIterations: Int = defaultMaxIterations

    private var tokensUsed: Int = 0
    private var iterationCount: Int = 0

    /// Limit granted by the last `softStopNotice()` call — consumed by `limitResult()`.
    private var lastGrantedLimit: Int?

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
        self.lastGrantedLimit = nil
        self.isActive = true
    }

    /// Reset budget for a new conversation turn.
    func reset() {
        isActive = false
        tokensUsed = 0
        iterationCount = 0
        lastGrantedLimit = nil
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

    // MARK: - Iteration Granting

    /// Grants one iteration for the tool about to run, or returns a wrap-up notice
    /// when the budget or iteration cap is exhausted.
    ///
    /// Call at the START of each tool's run(). Every execution consumes an iteration —
    /// including executions that later fail — so a model stuck retrying a failing tool
    /// is bounded by the same cap as a healthy loop.
    ///
    /// Not used by update_memory as a stop gate: memory writes are cheap, local,
    /// and must not be dropped. update_memory still calls `limitResult()` for
    /// truncation (which records its cost), but never checks `softStopNotice()`.
    func softStopNotice() -> [String: Any]? {
        guard isActive else {
            lastGrantedLimit = Self.inactiveLimit
            return nil
        }
        if shouldStop { return notice }
        lastGrantedLimit = consumeIteration()
        return nil
    }

    /// Consumes one iteration and returns the max tokens granted for this result
    /// (min 150, max 1500). Returns 2000 if the budget is inactive.
    func consumeIteration() -> Int {
        guard isActive else { return Self.inactiveLimit }

        if iterationCount >= maxIterations {
            return Self.minToolResultTokens
        }

        iterationCount += 1
        return limitForCurrentIteration()
    }

    /// The limit the NEXT granted iteration would allow, without consuming anything.
    /// Used by tools to decide whether expensive enrichment (e.g. page fetches) is
    /// worth doing when the budget is tight.
    func projectedResultLimit() -> Int {
        guard isActive else { return Self.inactiveLimit }
        if shouldStop { return Self.minToolResultTokens }
        let remaining = workingBudget - tokensUsed
        let remainingIterations = max(maxIterations - iterationCount, 1)
        let perIteration = remaining / remainingIterations
        return min(max(perIteration / 2, Self.minToolResultTokens), Self.maxToolResultTokens)
    }

    /// Per-iteration limit after the current iteration has been consumed.
    private func limitForCurrentIteration() -> Int {
        let remaining = workingBudget - tokensUsed
        let remainingIterations = max(maxIterations - iterationCount + 1, 1)
        let perIteration = remaining / remainingIterations
        return min(max(perIteration / 2, Self.minToolResultTokens), Self.maxToolResultTokens)
    }

    // MARK: - Tool Result Limiting (single entry point for all tools)

    /// Soft-stop guard: the wrap-up message the model sees when the budget is exhausted.
    private var notice: [String: Any] {
        [
            "notice": "Tool call budget for this turn is exhausted.",
            "hint": "Do NOT call more tools. Answer the user with the data you already have.",
        ]
    }

    /// Truncate a tool result to the limit granted by `softStopNotice()` (or grant one
    /// on the fly for tools that skip the guard, e.g. update_memory) and record the cost.
    func limitResult(_ result: Any) async -> Any {
        let limit = lastGrantedLimit ?? consumeIteration()
        lastGrantedLimit = nil
        let truncated = await TokenTruncator.truncateResult(result, maxTokens: limit)
        recordCost(tokens: min(estimateTokens(truncated), limit))
        return truncated
    }

    /// Rough token estimate, conservative for non-ASCII text: ASCII ≈ 4 chars/token,
    /// non-ASCII (Cyrillic, CJK, …) ≈ 1 char/token. Over-estimating is safe — the
    /// budget stops slightly early rather than overflowing the KV cache.
    static func estimateTokens(_ value: Any) -> Int {
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

    static func estimateTokens(of string: String) -> Int {
        var ascii = 0
        var nonAscii = 0
        for scalar in string.unicodeScalars {
            if scalar.isASCII { ascii += 1 } else { nonAscii += 1 }
        }
        return max(1, ascii / 4 + nonAscii)
    }

    private func estimateTokens(_ value: Any) -> Int {
        Self.estimateTokens(value)
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
