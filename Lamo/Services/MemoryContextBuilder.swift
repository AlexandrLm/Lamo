import Foundation
import os

struct MemoryContextBuilder {
    let maxFacts: Int
    let maxMemoryChars: Int
    let ageDecayHalfLife: Double
    let minSemanticScore: Double = 0.6

    private let logger = Logger(subsystem: LamoLogger.subsystem, category: "memory")

    // MARK: - Context Building

    func buildContext(
        factsCache: [MemoryEntry],
        embeddingService: EmbeddingService,
        lastQueryText: String,
        lastQueryEmbedding: EmbeddedText?,
        lastQueryEmbeddings: [EmbeddedText]? = nil
    ) -> (context: String, includedFacts: [MemoryEntry]) {
        guard !factsCache.isEmpty else { return ("", []) }

        let now = Date()
        let queryVecs = lastQueryEmbeddings ?? (lastQueryEmbedding.map { [$0] } ?? [])
        let useSemantic = embeddingService.isAvailable && !queryVecs.isEmpty && !lastQueryText.isEmpty

        var scored: [(fact: MemoryEntry, blended: Double, semantic: Double)] = []
        scored.reserveCapacity(factsCache.count)
        for fact in factsCache {
            let base = relevanceScore(fact: fact, now: now)
            var semantic = 0.0
            if useSemantic {
                semantic = max(0.0, Double(embeddingService.semanticSimilarity(queryVectors: queryVecs, factID: fact.id, factText: fact.text)))
            }
            let baseNorm = min(base / 3.0, 1.0)
            let blended = useSemantic ? baseNorm * 0.3 + semantic * 0.7 : base
            scored.append((fact, blended, semantic))
        }
        scored.sort {
            if $0.blended != $1.blended { return $0.blended > $1.blended }
            return $0.fact.timestamp > $1.fact.timestamp
        }

        var context = "<memory>\n"
        var totalChars = 0
        var includedFacts: [MemoryEntry] = []
        for entry in scored.prefix(maxFacts) {
            if useSemantic && entry.semantic < minSemanticScore { continue }
            let line = "• \(entry.fact.text)\n"
            if totalChars + line.count > maxMemoryChars { break }
            context += line
            totalChars += line.count
            includedFacts.append(entry.fact)
        }
        if includedFacts.isEmpty { return ("", []) }

        context += "</memory>"
        return (context: context, includedFacts: includedFacts)
    }

    // MARK: - Scoring

    func relevanceScore(fact: MemoryEntry, now: Date) -> Double {
        let ageDays = max(0.0, now.timeIntervalSince(fact.timestamp)) / 86400.0
        let decay = exp(-ageDays / ageDecayHalfLife)
        let usageBoost = 1.0 + Double(fact.usageCount) * 0.5
        return usageBoost * decay
    }

    func blendedScore(
        fact: MemoryEntry,
        now: Date,
        useSemantic: Bool,
        queryVec: EmbeddedText?,
        embeddingService: EmbeddingService
    ) -> Double {
        let base = relevanceScore(fact: fact, now: now)
        let baseNorm = min(base / 3.0, 1.0)
        guard useSemantic, let queryVec,
              let factVec = embeddingService.embedding(for: fact.id, text: fact.text) else {
            return base
        }
        let semantic = max(0.0, Double(embeddingService.cosineSimilarity(queryVec, factVec)))
        return baseNorm * 0.3 + semantic * 0.7
    }
}
