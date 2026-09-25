import Foundation
import NaturalLanguage
import os

/// A text embedding tagged with the model that produced it.
///
/// Different embedding models live in different vector spaces. Vectors with
/// different `modelKey`s must never be compared directly — `EmbeddingService`
/// returns similarity 0 for such pairs.
struct EmbeddedText {
    let vector: [Double]
    let modelKey: String
}

/// Semantic embedding service using Apple's on-device `NLContextualEmbedding`.
///
/// The legacy `NLEmbedding` static model has no Russian sentence model, so this
/// service uses `NLContextualEmbedding`, which ships a Cyrillic model covering
/// Russian, Ukrainian, Bulgarian, and Kazakh. This is what makes Russian
/// semantics work.
///
/// **Two gotchas discovered empirically (don't regress these):**
/// 1. **Case changes tokenization.** The Cyrillic model tokenizes `"Сегодня"`
///    into characters (`С/е/г/одн/я`) but `"сегодня"` as one token — so the same
///    fact capitalized differently produces an incompatible vector. Text is
///    lowercased before embedding so all vectors share one tokenization.
/// 2. **Mean-pooling over subword tokens is dominated by the shared alphabet**
///    (unrelated Russian sentences land at ~0.94 similarity). We pool per word
///    instead: average subword vectors within each whitespace-delimited word,
///    then average word vectors and L2-normalize. This restores discrimination
///    (unrelated ≈ 0.42–0.58, near-duplicates ≈ 0.84–0.97).
///
/// Model assets download over-the-air on first use (`requestAssets`). Until
/// they're ready `isAvailable == false` and callers degrade to text heuristics.
@MainActor
final class EmbeddingService {
    static let shared = EmbeddingService()

    /// Whether the Cyrillic (primary/Russian) model is ready for inference.
    private(set) var isAvailable: Bool = false
    /// Whether model assets are still downloading/loading.
    private(set) var isWarmingUp: Bool = false

    /// One contextual embedding model per writing script.
    private let latin: ContextualSlot
    private let cyrillic: ContextualSlot

    /// Cached embeddings keyed by fact UUID.
    private var cache: [UUID: EmbeddedText] = [:]
    /// Max cache entries before eviction.
    private let maxCacheSize = 200
    /// LRU tracking: fact IDs in access order (most recent last).
    private var lruOrder: [UUID] = []

    /// Language recognizer for auto-detection.
    private let recognizer = NLLanguageRecognizer()

    /// Languages covered by the Cyrillic contextual model.
    private static let cyrillicLanguages: Set<NLLanguage> = [.russian, .ukrainian, .bulgarian, .kazakh]
    /// Languages covered by the Latin contextual model.
    private static let latinLanguages: Set<NLLanguage> = [
        .croatian, .czech, .danish, .dutch, .english, .finnish, .french, .german,
        .hungarian, .indonesian, .italian, .norwegian, .polish, .portuguese,
        .romanian, .slovak, .swedish, .spanish, .turkish, .vietnamese,
    ]

    // MARK: - Init

    private init() {
        latin = ContextualSlot(script: .latin, label: "latin")
        cyrillic = ContextualSlot(script: .cyrillic, label: "cyrillic")

        // Russian is the app's primary language — download Cyrillic assets eagerly.
        isWarmingUp = true
        Task { @MainActor in
            let ready = await cyrillic.ensureReady()
            isWarmingUp = false
            if ready {
                isAvailable = true
                LamoLogger.memory.info("Embedding ready: Cyrillic contextual model loaded")
            } else {
                LamoLogger.memory.warning("Embedding assets unavailable — using text-based dedup")
            }
        }
    }

    // MARK: - Language Detection

    /// Detect the dominant language of a text string.
    /// Returns nil if detection fails (text too short or mixed).
    func detectLanguage(_ text: String) -> NLLanguage? {
        recognizer.reset()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage,
              recognizer.languageHypotheses(withMaximum: 1)[lang] ?? 0 >= 0.5 else {
            return nil
        }
        return lang
    }

    /// Pick the model slot for a language; triggers a lazy asset download for
    /// the Latin model on first use (Cyrillic is always pre-warmed).
    private func slot(for language: NLLanguage?) -> ContextualSlot? {
        guard let lang = language else {
            latin.warmIfNeeded()
            return latin
        }
        if Self.cyrillicLanguages.contains(lang) { return cyrillic }
        if Self.latinLanguages.contains(lang) {
            latin.warmIfNeeded()
            return latin
        }
        return nil
    }

    // MARK: - Public API

    /// Generate an embedding for a text string.
    /// Auto-detects the language and selects the matching contextual model.
    /// Returns nil if the model isn't ready or the language is unsupported.
    func embed(_ text: String) -> EmbeddedText? {
        let lang = detectLanguage(text)
        return embed(text, language: lang)
    }

    /// Generate an embedding with an explicit language hint.
    func embed(_ text: String, language: NLLanguage?) -> EmbeddedText? {
        guard let slot = slot(for: language) else { return nil }
        guard let vector = slot.embed(text.lowercased()) else { return nil }
        return EmbeddedText(vector: vector, modelKey: slot.label)
    }

    /// Get cached embedding for a fact, computing it if needed.
    func embedding(for factID: UUID, text: String) -> EmbeddedText? {
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

    /// Compute cosine similarity between two embeddings (0...1).
    /// Vectors from different models live in different spaces — returns 0.
    func cosineSimilarity(_ a: EmbeddedText, _ b: EmbeddedText) -> Float {
        guard a.modelKey == b.modelKey,
              a.vector.count == b.vector.count,
              !a.vector.isEmpty else { return 0 }

        var dotProduct: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        for i in 0..<a.vector.count {
            dotProduct += a.vector[i] * b.vector[i]
            normA += a.vector[i] * a.vector[i]
            normB += b.vector[i] * b.vector[i]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return Float(dotProduct / denominator)
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

/// Manages one `NLContextualEmbedding` model: asset download, loading, and
/// sentence-vector inference with word-aware pooling. Text passed to `embed`
/// should already be lowercased.
@MainActor
private final class ContextualSlot {
    let label: String
    private let script: NLScript
    private var model: NLContextualEmbedding?
    private var isReady = false
    private var assetRequested = false

    init(script: NLScript, label: String) {
        self.script = script
        self.label = label
    }

    /// Kick off an asset download if not already requested (lazy warm-up for the
    /// non-primary scripts). Returns immediately.
    func warmIfNeeded() {
        guard !isReady, !assetRequested else { return }
        assetRequested = true
        Task { @MainActor in
            _ = await ensureReady()
        }
    }

    /// Ensure assets are on device and the model is loaded. Returns true when ready.
    func ensureReady() async -> Bool {
        if isReady { return true }
        assetRequested = true
        guard let model = model ?? NLContextualEmbedding(script: script) else { return false }
        self.model = model

        if !model.hasAvailableAssets {
            let result: NLContextualEmbedding.AssetsResult
            do {
                result = try await model.requestAssets()
            } catch {
                LamoLogger.memory.error("Embedding asset request error (\(self.label)): \(error)")
                return false
            }
            guard result == .available else {
                LamoLogger.memory.warning("Embedding assets unavailable for \(self.label)")
                return false
            }
        }
        do {
            try model.load()
            isReady = true
        } catch {
            LamoLogger.memory.error("Embedding model load error (\(self.label)): \(error)")
        }
        return isReady
    }

    /// Compute a sentence embedding via word-aware pooling. Text should be lowercased.
    func embed(_ text: String) -> [Double]? {
        guard isReady, let model else { return nil }
        guard let result = try? model.embeddingResult(for: text, language: nil) else { return nil }
        return Self.wordAwareVector(from: result, text: text, dimension: model.dimension)
    }

    /// Mean-pool subword vectors per whitespace-delimited word, then average the
    /// word vectors and L2-normalize. See `EmbeddingService` docs for why.
    private static func wordAwareVector(from result: NLContextualEmbeddingResult, text: String, dimension: Int) -> [Double]? {
        var words: [[[Double]]] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            guard let (vec, range) = result.tokenVector(at: idx) else {
                idx = text.index(after: idx)
                continue
            }
            if vec.count == dimension {
                let isWordStart = range.lowerBound == text.startIndex
                    || text[text.index(before: range.lowerBound)] == " "
                if isWordStart { words.append([]) }
                words[words.count - 1].append(vec)
            }
            idx = range.upperBound
        }
        guard !words.isEmpty else { return nil }

        var sum = [Double](repeating: 0, count: dimension)
        for word in words {
            var wordVec = [Double](repeating: 0, count: dimension)
            for vec in word {
                for i in 0..<dimension { wordVec[i] += vec[i] }
            }
            for i in 0..<dimension { sum[i] += wordVec[i] / Double(word.count) }
        }
        let mean = sum.map { $0 / Double(words.count) }
        let norm = sqrt(mean.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        return mean.map { $0 / norm }
    }
}
