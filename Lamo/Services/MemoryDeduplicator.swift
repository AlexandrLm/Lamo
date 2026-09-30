import Foundation

enum MemoryDeduplicator {

    // MARK: - Text-Based Deduplication

    static func isDuplicateText(
        _ newFact: String,
        existingFacts: [MemoryEntry],
        wordSetsCache: inout [UUID: Set<String>],
        normalizedCache: inout [UUID: String]
    ) -> Bool {
        let newWords = wordSet(from: newFact)
        guard !newWords.isEmpty else { return true }

        let newNormalized = normalizeText(newFact)
        let wordCount = newWords.count

        let jaccardThreshold: Float = wordCount <= 5 ? 0.75 : 0.60

        for existing in existingFacts {
            let existingWords: Set<String>
            if let cached = wordSetsCache[existing.id] {
                existingWords = cached
            } else {
                existingWords = wordSet(from: existing.text)
                wordSetsCache[existing.id] = existingWords
            }

            let intersection = newWords.intersection(existingWords)
            let union = newWords.union(existingWords)
            if !union.isEmpty {
                let similarity = Float(intersection.count) / Float(union.count)
                if similarity > jaccardThreshold { return true }
            }

            let existingNormalized: String
            if let cached = normalizedCache[existing.id] {
                existingNormalized = cached
            } else {
                existingNormalized = normalizeText(existing.text)
                normalizedCache[existing.id] = existingNormalized
            }
            if newNormalized == existingNormalized { return true }

            if newNormalized.count > 10 && existingNormalized.count > 10 {
                if newNormalized.contains(existingNormalized) || existingNormalized.contains(newNormalized) {
                    let ratio = Double(min(newNormalized.count, existingNormalized.count))
                                / Double(max(newNormalized.count, existingNormalized.count))
                    if ratio > 0.7 { return true }
                }
            }
        }

        return false
    }

    // MARK: - Embedding-Based Deduplication

    static func isDuplicateEmbedding(
        _ newFact: String,
        existingFacts: [MemoryEntry],
        embeddingService: EmbeddingService,
        threshold: Float
    ) -> Bool {
        guard embeddingService.isAvailable else { return false }

        let newVecs = embeddingService.embedAll(newFact)
        guard !newVecs.isEmpty else { return false }

        for existing in existingFacts {
            let sim = embeddingService.semanticSimilarity(queryVectors: newVecs, factID: existing.id, factText: existing.text)
            if sim > threshold {
                return true
            }
        }
        return false
    }

    // MARK: - Conflict Detection

    static let singleValuedHints: Set<String> = [
        "name", "age", "born", "birthday", "birth", "lives", "living",
        "address", "phone", "email", "job", "works", "working",
        "married", "spouse", "husband", "wife", "city", "country",
        "language", "speaks", "called", "named"
    ]

    static func findConflictingFact(
        _ newFact: String,
        existingFacts: [MemoryEntry],
        wordSetsCache: [UUID: Set<String>],
        normalizedCache: [UUID: String]
    ) -> UUID? {
        let newSubject = extractSubject(newFact)
        guard newSubject.count >= 2 else { return nil }
        guard newSubject.contains(where: { singleValuedHints.contains($0) }) else { return nil }
        let newPrefix = Array(newSubject.prefix(2))

        for existing in existingFacts {
            let existingSubject = extractSubject(existing.text)
            guard existingSubject.count >= 2 else { continue }
            let existingPrefix = Array(existingSubject.prefix(2))
            guard newPrefix == existingPrefix else { continue }

            let newWords = wordSet(from: newFact)
            let existingWords = wordSet(from: existing.text)
            if newWords.isSubset(of: existingWords) || existingWords.isSubset(of: newWords) {
                continue
            }
            let intersection = newWords.intersection(existingWords)
            let union = newWords.union(existingWords)
            guard !union.isEmpty else { continue }
            let similarity = Float(intersection.count) / Float(union.count)

            if similarity < 0.5 {
                return existing.id
            }
        }
        return nil
    }

    // MARK: - Subject Extraction

    /// Extract the "subject" of a fact — the first 2-3 content words.
    /// Handles patterns like "User's name is X" → ["user", "name"]
    /// or "User lives in City" → ["user", "lives"]
    static func extractSubject(_ text: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "is", "are", "was", "were",
            "has", "have", "had", "in", "on", "at", "to",
            "for", "of", "with", "by", "from", "as", "or",
            "and", "but", "not", "no", "yes", "very", "just",
            "that", "this", "it", "its", "he", "she", "they",
            "his", "her", "their", "my", "your", "our",
            "there", "here", "about", "would", "could", "should",
            "will", "can", "do", "does", "did", "get", "got",
            "want", "need", "know", "think"
        ]
        let words = text
            .replacingOccurrences(of: "'s", with: "")
            .lowercased()
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return Array(words.prefix(3))
    }

    // MARK: - Text Utilities

    /// Extract lowercase word set from text for similarity comparison.
    static func wordSet(from text: String) -> Set<String> {
        let words = text.lowercased()
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        return Set(words)
    }

    /// Normalize text for comparison: lowercase, strip punctuation, normalize whitespace.
    static func normalizeText(_ text: String) -> String {
        let lowercased = text.lowercased()
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
        let cleaned = String(lowercased.unicodeScalars.filter { allowed.contains($0) })
        let words = cleaned.split(separator: " ").map(String.init)
        return words.joined(separator: " ")
    }
}
