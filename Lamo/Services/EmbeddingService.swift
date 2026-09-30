import Foundation
import NaturalLanguage
import os

struct EmbeddedText {
    let vector: [Double]
    let modelKey: String
}

@MainActor
final class EmbeddingService {
    static let shared = EmbeddingService()

    var isAvailable: Bool { cyrillic.isReady || latin.isReady }
    private(set) var isWarmingUp: Bool = false

    private let latin: ContextualSlot
    private let cyrillic: ContextualSlot

    private var cache: [String: EmbeddedText] = [:]
    private let maxCacheSize = 200
    private var lruOrder: [String] = []

    private let recognizer = NLLanguageRecognizer()

    private static let cyrillicLanguages: Set<NLLanguage> = [.russian, .ukrainian, .bulgarian, .kazakh]
    private static let latinLanguages: Set<NLLanguage> = [
        .croatian, .czech, .danish, .dutch, .english, .finnish, .french, .german,
        .hungarian, .indonesian, .italian, .norwegian, .polish, .portuguese,
        .romanian, .slovak, .swedish, .spanish, .turkish, .vietnamese,
    ]

    // MARK: - Init

    private init() {
        latin = ContextualSlot(script: .latin, label: "latin")
        cyrillic = ContextualSlot(script: .cyrillic, label: "cyrillic")

        isWarmingUp = true
        Task { @MainActor in
            let cyrillicReady = await cyrillic.ensureReady()
            let latinReady = await latin.ensureReady()
            let ready = cyrillicReady || latinReady
            isWarmingUp = false
            if ready {
                LamoLogger.memory.info("Embedding ready")
            } else {
                LamoLogger.memory.warning("Embedding assets unavailable — using text-based dedup")
            }
        }
    }

    // MARK: - Language Detection

    func detectLanguage(_ text: String) -> NLLanguage? {
        recognizer.reset()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage,
              recognizer.languageHypotheses(withMaximum: 1)[lang] ?? 0 >= 0.5 else {
            return nil
        }
        return lang
    }

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

    func embed(_ text: String) -> EmbeddedText? {
        let lang = detectLanguage(text)
        return embed(text, language: lang)
    }

    func embed(_ text: String, language: NLLanguage?) -> EmbeddedText? {
        guard let slot = slot(for: language) else { return nil }
        guard let vector = slot.embed(text.lowercased()) else { return nil }
        return EmbeddedText(vector: vector, modelKey: slot.label)
    }

    func embedAll(_ text: String) -> [EmbeddedText] {
        let lowered = text.lowercased()
        var result: [EmbeddedText] = []
        if let vec = cyrillic.embed(lowered) {
            result.append(EmbeddedText(vector: vec, modelKey: cyrillic.label))
        }
        if let vec = latin.embed(lowered) {
            result.append(EmbeddedText(vector: vec, modelKey: latin.label))
        }
        if result.isEmpty, let fallback = embed(text) {
            result.append(fallback)
        }
        return result
    }

    func embedding(for factID: UUID, text: String) -> EmbeddedText? {
        let all = embeddingAll(for: factID, text: text)
        if let lang = detectLanguage(text) {
            if Self.cyrillicLanguages.contains(lang) {
                return all.first { $0.modelKey == cyrillic.label } ?? all.first
            } else {
                return all.first { $0.modelKey == latin.label } ?? all.first
            }
        }
        return all.first
    }

    func embeddingAll(for factID: UUID, text: String) -> [EmbeddedText] {
        let lowered = text.lowercased()
        var result: [EmbeddedText] = []
        for slot in [cyrillic, latin] {
            let key = cacheKey(id: factID, modelKey: slot.label)
            if let cached = cache[key] {
                touchLRU(key)
                result.append(cached)
                continue
            }
            guard let vec = slot.embed(lowered) else { continue }
            let embedded = EmbeddedText(vector: vec, modelKey: slot.label)
            cache[key] = embedded
            touchLRU(key)
            result.append(embedded)
        }
        evictIfNeeded()
        return result
    }

    func semanticSimilarity(queryVectors: [EmbeddedText], factID: UUID, factText: String) -> Float {
        let factVectors = embeddingAll(for: factID, text: factText)
        var best: Float = 0
        for q in queryVectors {
            for f in factVectors where f.modelKey == q.modelKey {
                best = max(best, cosineSimilarity(q, f))
            }
        }
        return best
    }

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
        return max(-1, min(1, Float(dotProduct / denominator)))
    }

    func remove(ids: [UUID]) {
        for id in ids {
            for modelKey in [cyrillic.label, latin.label] {
                let key = cacheKey(id: id, modelKey: modelKey)
                cache.removeValue(forKey: key)
                lruOrder.removeAll { $0 == key }
            }
        }
    }

    func removeAll() {
        cache.removeAll()
        lruOrder.removeAll()
    }

    // MARK: - Private

    private func cacheKey(id: UUID, modelKey: String) -> String {
        "\(id.uuidString)-\(modelKey)"
    }

    private func touchLRU(_ key: String) {
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
    }

    private func evictIfNeeded() {
        while lruOrder.count > maxCacheSize, let oldest = lruOrder.first {
            cache.removeValue(forKey: oldest)
            lruOrder.removeFirst()
        }
    }
}

@MainActor
private final class ContextualSlot {
    let label: String
    private let script: NLScript
    private var model: NLContextualEmbedding?
    var isReady = false
    private var assetRequested = false

    init(script: NLScript, label: String) {
        self.script = script
        self.label = label
    }

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

    private static func wordAwareVector(from result: NLContextualEmbeddingResult, text: String, dimension: Int) -> [Double]? {
        var words: [[[Double]]] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            guard let (vec, range) = result.tokenVector(at: idx) else {
                idx = text.index(after: idx)
                continue
            }
            if vec.count == dimension {
                let isWordStart: Bool
                if range.lowerBound == text.startIndex {
                    isWordStart = true
                } else {
                    let prev = text[text.index(before: range.lowerBound)]
                    isWordStart = prev.isWhitespace || prev.isPunctuation
                }
                if isWordStart || words.isEmpty { words.append([]) }
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
