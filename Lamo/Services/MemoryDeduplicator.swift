import Foundation

/// Static deduplication helpers for memory facts.
/// Extracted from MemoryService to reduce complexity.
enum MemoryDeduplicator {

    // MARK: - Text-Based Deduplication

    /// Check if a fact is too similar to any existing fact using word-set comparison.
    /// Uses two-stage detection:
    /// 1. Jaccard similarity on word sets (fast, catches rephrasings)
    /// 2. Normalized text comparison (catches near-identical text)
    /// Threshold adapts to fact length — shorter facts need higher similarity to be duplicates.
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

        // Stricter threshold for short facts (3-5 words can overlap by chance)
        let jaccardThreshold: Float = wordCount <= 5 ? 0.75 : 0.60

        for existing in existingFacts {
            let existingWords: Set<String>
            if let cached = wordSetsCache[existing.id] {
                existingWords = cached
            } else {
                // Fallback: compute on the fly if cache is missing
                existingWords = wordSet(from: existing.text)
                wordSetsCache[existing.id] = existingWords
            }

            // Jaccard similarity check
            let intersection = newWords.intersection(existingWords)
            let union = newWords.union(existingWords)
            if !union.isEmpty {
                let similarity = Float(intersection.count) / Float(union.count)
                if similarity > jaccardThreshold { return true }
            }

            // Normalized text comparison (catches "User is 25" vs "User is 25 years old")
            let existingNormalized: String
            if let cached = normalizedCache[existing.id] {
                existingNormalized = cached
            } else {
                existingNormalized = normalizeText(existing.text)
                normalizedCache[existing.id] = existingNormalized
            }
            if newNormalized == existingNormalized { return true }

            // One is a substring of the other after normalization
            if newNormalized.count > 10 && existingNormalized.count > 10 {
                if newNormalized.contains(existingNormalized) || existingNormalized.contains(newNormalized) {
                    // Only flag if length ratio is close (avoids "I like pizza" matching "I like pizza with extra cheese and pepperoni")
                    let ratio = Double(min(newNormalized.count, existingNormalized.count))
                                / Double(max(newNormalized.count, existingNormalized.count))
                    if ratio > 0.7 { return true }
                }
            }
        }

        return false
    }

    // MARK: - Embedding-Based Deduplication

    /// Async embedding-based duplicate check.
    /// Computes embedding for the new fact and checks cosine similarity against all cached facts.
    /// Falls back to false (not a duplicate) if embeddings are unavailable or computation fails.
    static func isDuplicateEmbedding(
        _ newFact: String,
        existingFacts: [MemoryEntry],
        embeddingService: EmbeddingService,
        threshold: Float
    ) -> Bool {
        guard embeddingService.isAvailable else { return false }

        guard let newVec = embeddingService.embed(newFact) else { return false }

        for existing in existingFacts {
            guard let existingVec = embeddingService.embedding(for: existing.id, text: existing.text) else {
                continue
            }
            let sim = embeddingService.cosineSimilarity(newVec, existingVec)
            if sim > threshold {
                return true
            }
        }
        return false
    }

    // MARK: - Conflict Detection

    /// Find an existing fact that conflicts with the new one.
    /// Conflict = same subject entity but different/contradictory predicate.
    /// Heuristic: extract the "subject" (first noun phrase or first 2-3 words)
    /// and check if an existing fact shares the subject but differs in the rest.
    static func findConflictingFact(
        _ newFact: String,
        existingFacts: [MemoryEntry],
        wordSetsCache: [UUID: Set<String>],
        normalizedCache: [UUID: String]
    ) -> UUID? {
        // Extract subject: first few words (up to first significant word boundary)
        let newSubject = extractSubject(newFact)
        guard newSubject.count >= 2 else { return nil }

        for existing in existingFacts {
            let existingSubject = extractSubject(existing.text)
            guard existingSubject.count >= 2 else { continue }

            // Same subject?
            let subjectIntersection = Set(newSubject).intersection(Set(existingSubject))
            guard subjectIntersection.count >= newSubject.count - 1 else { continue }

            // But different rest of the fact? (not just a rephrase)
            let newWords = wordSet(from: newFact)
            let existingWords = wordSet(from: existing.text)
            let intersection = newWords.intersection(existingWords)
            let union = newWords.union(existingWords)
            guard !union.isEmpty else { continue }
            let similarity = Float(intersection.count) / Float(union.count)

            // Same subject but low overall similarity → likely contradiction
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
