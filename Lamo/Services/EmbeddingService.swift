import Foundation
import NaturalLanguage
import CoreML
import os

/// Semantic embedding service using Apple's on-device NLContextualEmbedding.
///
/// Provides 768-dim sentence embeddings via a built-in BERT model, fully on-device,
/// ANE-accelerated. Used by MemoryService for semantic deduplication and relevance ranking.
///
/// Fallback: if the embedding model fails (unlikely on iOS 17+), the service
/// gracefully degrades — MemoryService uses text-based heuristics instead.
@MainActor
final class EmbeddingService {
    static let shared = EmbeddingService()

    /// Whether the embedding model loaded successfully.
    private(set) var isAvailable: Bool = false

    /// Cached embeddings keyed by fact UUID.
    private var cache: [UUID: [Float]] = [:]
    /// Max cache entries before eviction.
    private let maxCacheSize = 200
    /// LRU tracking: fact IDs in access order (most recent last).
    private var lruOrder: [UUID] = []

    /// The NLContextualEmbedding model (768-dim BERT).
    private let model: NLContextualEmbedding

    // MARK: - Init

    private init() {
        // NLContextualEmbedding loads a built-in multilingual BERT model.
        self.model = NLContextualEmbedding(language: .english)

        // Verify the model actually works by requesting a test embedding.
        // This triggers model loading so subsequent calls are fast.
        let testResult = Self.testEmbedding(model: self.model)
        self.isAvailable = testResult
        if testResult {
            LamoLogger.memory.info("NLContextualEmbedding ready (768-dim BERT)")
        } else {
            LamoLogger.memory.warning("NLContextualEmbedding unavailable — using text-based dedup")
        }
    }

    /// Synchronous test to verify embedding model loads and returns valid data.
    private static func testEmbedding(model: NLContextualEmbedding) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        model.requestEmbeddings(for: ["test"]) { embeddings, error in
            defer { semaphore.signal() }
            guard error == nil, let emb = embeddings, emb.count == 1, emb[0].count >= 256 else {
                return
            }
            let ptr = emb[0].dataPointer.bindMemory(to: Float.self, capacity: emb[0].count)
            success = !ptr[0].isNaN
        }
        _ = semaphore.wait(timeout: .now() + 15)
        return success
    }

    // MARK: - Public API

    /// Generate embedding vector for a text string.
    /// Returns nil if embedding fails or service is unavailable.
    func embed(_ text: String) async -> [Float]? {
        guard isAvailable else { return nil }

        return await withCheckedContinuation { continuation in
            model.requestEmbeddings(for: [text]) { embeddings, error in
                if let error {
                    LamoLogger.memory.error("Embedding failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let mlArrays = embeddings, let first = mlArrays.first, first.count > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let count = first.count
                let ptr = first.dataPointer.bindMemory(to: Float.self, capacity: count)
                let vec = Array(UnsafeBufferPointer(start: ptr, count: count))
                continuation.resume(returning: vec)
            }
        }
    }

    /// Get cached embedding for a fact, computing it if needed.
    func embedding(for factID: UUID, text: String) async -> [Float]? {
        if let cached = cache[factID] {
            touchLRU(factID)
            return cached
        }
        guard let vec = await embed(text) else { return nil }
        cache[factID] = vec
        lruOrder.append(factID)
        evictIfNeeded()
        return vec
    }

    /// Compute cosine similarity between two embedding vectors (0...1).
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return max(0, min(1, dotProduct / denominator))
    }

    /// Remove cached embedding.
    func invalidate(factID: UUID) {
        cache.removeValue(forKey: factID)
        lruOrder.removeAll { $0 == factID }
    }

    /// Clear all cached embeddings.
    func invalidateAll() {
        cache.removeAll(keepingCapacity: true)
        lruOrder.removeAll(keepingCapacity: true)
    }

    // MARK: - Private

    private func touchLRU(_ id: UUID) {
        lruOrder.removeAll { $0 == id }
        lruOrder.append(id)
    }

    private func evictIfNeeded() {
        while cache.count > maxCacheSize, let oldest = lruOrder.first {
            cache.removeValue(forKey: oldest)
            lruOrder.removeFirst()
        }
    }
}
