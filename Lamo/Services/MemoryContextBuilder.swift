import Foundation
import os

/// Builds memory context strings for injection into system prompts.
///
/// Extracted from MemoryService to reduce complexity.
/// Sorts facts by a blended score combining usage/recency with semantic similarity,
/// then builds a formatted context string within character limits.
struct MemoryContextBuilder {
    let maxFacts: Int
    let maxMemoryChars: Int
    let ageDecayHalfLife: Double

    // MARK: - Logging

    private let logger = Logger(subsystem: LamoLogger.subsystem, category: "memory")

    // MARK: - Context Building

    /// Build memory context string for injection into system prompt.
    /// Facts are sorted by relevance score: blend of usage count and recency with age decay.
    /// - Parameters:
    ///   - factsCache: All cached memory entries to rank and filter.
    ///   - embeddingService: Service for semantic similarity scoring.
    ///   - lastQueryText: The user's last query text (unused here; kept for API compatibility).
    ///   - lastQueryEmbedding: Pre-computed embedding for the last user query.
    /// - Returns: A tuple of the formatted context string and the facts included in it.
    func buildContext(
        factsCache: [MemoryEntry],
        embeddingService: EmbeddingService,
        lastQueryText: String,
        lastQueryEmbedding: [Double]?
    ) -> (context: String, includedFacts: [MemoryEntry]) {
        guard !factsCache.isEmpty else { return ("", []) }

        var context = "<memory>\n"
        // Sort by blended score: usage/recency + semantic similarity to query.
        // When embeddings are available AND query context is set, semantic relevance
        // dominates (0.7 weight); otherwise pure relevance score.
        let now = Date()
        let useSemantic = embeddingService.isAvailable && lastQueryEmbedding != nil
        let queryVec = lastQueryEmbedding

        let sorted = factsCache.sorted { a, b in
            let scoreA = blendedScore(
                fact: a, now: now,
                useSemantic: useSemantic, queryVec: queryVec,
                embeddingService: embeddingService
            )
            let scoreB = blendedScore(
                fact: b, now: now,
                useSemantic: useSemantic, queryVec: queryVec,
                embeddingService: embeddingService
            )
            if scoreA != scoreB { return scoreA > scoreB }
            return a.timestamp > b.timestamp
        }

        var totalChars = 0
        var includedFacts: [MemoryEntry] = []
        for fact in sorted.prefix(maxFacts) {
            let line = "• \(fact.text)\n"
            if totalChars + line.count > maxMemoryChars { break }
            context += line
            totalChars += line.count
            includedFacts.append(fact)
        }

        context += "</memory>"
        return (context: context, includedFacts: includedFacts)
    }

    // MARK: - Scoring

    /// Relevance score for context sorting.
    ///
    /// Combines usage frequency with recency using exponential decay.
    /// - A fact used 10 times yesterday scores higher than one used 10 times 3 months ago.
    /// - A fact never used (usageCount=0) still gets a small baseline from recency.
    ///
    /// Formula: `(1.0 + usageCount * 0.5) * exp(-ageDays / ageDecayHalfLife)`
    func relevanceScore(fact: MemoryEntry, now: Date) -> Double {
        let ageDays = max(0.0, now.timeIntervalSince(fact.timestamp)) / 86400.0
        let decay = exp(-ageDays / ageDecayHalfLife)
        // Base score of 1 ensures new facts get ranked even without usage.
        // usageCount amplifies frequently-referenced facts.
        let usageBoost = 1.0 + Double(fact.usageCount) * 0.5
        return usageBoost * decay
    }

    /// Blended score: relevance (usage count + recency) combined with semantic similarity.
    ///
    /// When embeddings are available, semantic relevance dominates (0.7 weight).
    /// Falls back to pure relevance score when embeddings or query vector are unavailable.
    ///
    /// Formula: `relevanceScore * 0.3 + cosineSimilarity * 0.7`
    func blendedScore(
        fact: MemoryEntry,
        now: Date,
        useSemantic: Bool,
        queryVec: [Double]?,
        embeddingService: EmbeddingService
    ) -> Double {
        let base = relevanceScore(fact: fact, now: now)
        guard useSemantic, let queryVec,
              let factVec = embeddingService.embedding(for: fact.id, text: fact.text) else {
            return base
        }
        let semantic = Double(embeddingService.cosineSimilarity(queryVec, factVec))
        return base * 0.3 + semantic * 0.7
    }
}
