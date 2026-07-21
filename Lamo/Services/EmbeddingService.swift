import Foundation
import NaturalLanguage
import os

/// Semantic embedding service using Apple's on-device NLEmbedding (sentence embeddings).
///
/// Provides sentence embeddings via a built-in model, fully on-device, ANE-accelerated.
/// Used by MemoryService for semantic deduplication and relevance ranking.
///
/// Fallback: if the embedding model fails to load, the service gracefully degrades —
/// MemoryService uses text-based heuristics instead.
@MainActor
final class EmbeddingService {
    static let shared = EmbeddingService()

    /// Whether the embedding model loaded successfully.
    private(set) var isAvailable: Bool = false

    /// Cached embeddings keyed by fact UUID.
    private var cache: [UUID: [Double]] = [:]
    /// Max cache entries before eviction.
    private let maxCacheSize = 200
    /// LRU tracking: fact IDs in access order (most recent last).
    private var lruOrder: [UUID] = []

    /// The NLEmbedding model for sentence embeddings.
    private let model: NLEmbedding?

    // MARK: - Init

    private init() {
        self.model = NLEmbedding.sentenceEmbedding(for: .english)

        if let model {
            let testResult = Self.testEmbedding(model: model)
            self.isAvailable = testResult
        }

        if isAvailable {
            LamoLogger.memory.info("NLEmbedding ready (sentence embedding model)")
        } else {
            LamoLogger.memory.warning("NLEmbedding unavailable — using text-based dedup")
        }
    }

    /// Synchronous test to verify embedding model loads and returns valid data.
    private static func testEmbedding(model: NLEmbedding) -> Bool {
        guard let vector = try? model.vector(for: "test"),
              !vector.isEmpty else { return false }
        return !vector[0].isNaN
    }

    // MARK: - Public API

    /// Generate embedding vector for a text string.
    /// Returns nil if embedding fails or service is unavailable.
    func embed(_ text: String) -> [Double]? {
        guard isAvailable, let model else { return nil }
        guard let vector = try? model.vector(for: text), !vector.isEmpty else { return nil }
        return vector
    }

    /// Get cached embedding for a fact, computing it if needed.
    func embedding(for factID: UUID, text: String) -> [Double]? {
        if let cached = cache[factID] {
            touchLRU(factID)
            return cached
        }
        guard let vec = embed(text) else { return nil }
        cache[factID] = vec
        touchLRU(factID)
        evictIfNeeded()
        return vec
    }

    /// Compute cosine similarity between two embedding vectors (0...1).
    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return Float(dotProduct / denominator)
    }

    /// Remove cached embedding.
    func invalidate(factID: UUID) {
        cache.removeValue(forKey: factID)
        lruOrder.removeAll { $0 == factID }
    }

    /// Clear all cached embeddings.
    func invalidateAll() {
        cache.removeAll()
        lruOrder.removeAll()
    }

    // MARK: - Private

    private func touchLRU(_ id: UUID) {
        lruOrder.removeAll { $0 == id }
        lruOrder.append(id)
    }

    private func evictIfNeeded() {
        while lruOrder.count > maxCacheSize, let oldest = lruOrder.first {
            cache.removeValue(forKey: oldest)
            lruOrder.removeFirst()
        }
    }
}
