import Foundation

actor AgenticLoopBudget {
    static let shared = AgenticLoopBudget()

    static let reservedForReply = 512
    static let defaultMaxIterations = 5
    static let minToolResultTokens = 150
    static let maxToolResultTokens = 1500
    private static let inactiveLimit = 2000

    // MARK: - State

    private var totalBudget: Int = 4096
    private var systemOverhead: Int = 0
    private var conversationSkeletonTokens: Int = 0
    private var maxIterations: Int = defaultMaxIterations

    private var tokensUsed: Int = 0
    private var iterationCount: Int = 0

    private var grantedLimits: [Int] = []

    private(set) var isActive: Bool = false

    // MARK: - Configuration

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
        self.grantedLimits = []
        self.isActive = true
    }

    func reset() {
        isActive = false
        tokensUsed = 0
        iterationCount = 0
        grantedLimits = []
    }

    // MARK: - Budget Queries

    var workingBudget: Int {
        max(0, totalBudget - systemOverhead - conversationSkeletonTokens - Self.reservedForReply)
    }

    var shouldStop: Bool {
        iterationCount >= maxIterations || tokensUsed >= workingBudget
    }

    var headroom: Int {
        max(0, workingBudget - tokensUsed)
    }

    // MARK: - Iteration Granting

    func softStopNotice() -> [String: Any]? {
        guard isActive else {
            grantedLimits.append(Self.inactiveLimit)
            return nil
        }
        if shouldStop { return notice }
        grantedLimits.append(consumeIteration())
        return nil
    }

    func consumeIteration() -> Int {
        guard isActive else { return Self.inactiveLimit }

        if iterationCount >= maxIterations {
            return Self.minToolResultTokens
        }

        iterationCount += 1
        return limitForCurrentIteration()
    }

    func projectedResultLimit() -> Int {
        guard isActive else { return Self.inactiveLimit }
        if shouldStop { return Self.minToolResultTokens }
        let remaining = workingBudget - tokensUsed
        let remainingIterations = max(maxIterations - iterationCount, 1)
        let perIteration = remaining / remainingIterations
        return min(max(perIteration / 2, Self.minToolResultTokens), Self.maxToolResultTokens)
    }

    private func limitForCurrentIteration() -> Int {
        let remaining = workingBudget - tokensUsed
        let remainingIterations = max(maxIterations - iterationCount + 1, 1)
        let perIteration = remaining / remainingIterations
        return min(max(perIteration / 2, Self.minToolResultTokens), Self.maxToolResultTokens)
    }

    // MARK: - Tool Result Limiting (single entry point for all tools)

    private var notice: [String: Any] {
        [
            "notice": "Tool call budget for this turn is exhausted.",
            "hint": "Do NOT call more tools. Answer the user with the data you already have.",
        ]
    }

    func limitResult(_ result: Any) async -> Any {
        let limit: Int
        if grantedLimits.isEmpty {
            limit = consumeIteration()
        } else {
            limit = grantedLimits.removeFirst()
        }
        let truncated = await TokenTruncator.truncateResult(result, maxTokens: limit)
        recordCost(tokens: min(estimateTokens(truncated), limit))
        return truncated
    }

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

    func recordCost(tokens: Int) {
        tokensUsed += tokens
    }

    var currentIteration: Int { iterationCount }

    var totalIterations: Int { iterationCount }
}
