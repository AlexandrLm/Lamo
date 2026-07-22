import Foundation
import SwiftData
import Combine
import os

/// Semantic memory that stores facts about the user.
///
/// Architecture:
/// 1. During LLM response → model calls update_memory tool with facts
/// 2. Facts stored as plain text in SwiftData
/// 3. Embeddings computed via NLContextualEmbedding (on-device BERT) for semantic dedup
/// 4. Before each LLM call → semantically relevant facts injected into system prompt
///
/// Hybrid approach: embeddings for semantic understanding + text heuristics as fallback.
@MainActor
final class MemoryService: ObservableObject {
    static let shared = MemoryService()

    @Published var isEnabled: Bool = AppDefaults.memoryEnabled.wrappedValue {
        didSet {
            AppDefaults.memoryEnabled.wrappedValue = isEnabled
        }
    }

    @Published var totalEntries: Int = 0

    private(set) var modelContext: ModelContext?
    private var factsCache: [MemoryEntry] = []
    private var cacheLoaded = false
    /// Cached result of buildMemoryContext() — invalidated on any fact change.
    private var memoryContextCache: String?
    /// Cached word sets for duplicate detection — computed on load, updated on mutation.
    private var wordSetsCache: [UUID: Set<String>] = [:]
    /// Cached normalized text for conflict detection.
    private var normalizedCache: [UUID: String] = [:]
    /// Cache for the full system prompt including memory — invalidated on fact/summary change.
    private var systemPromptCache: (base: String, conversationID: UUID?, result: String)?

    /// Current conversation ID — set by ChatViewModel before each message.
    /// Used by UpdateMemoryTool to update conversation summary.
    var currentConversationID: UUID?
    /// Max facts to inject into system prompt.
    private let maxFacts = 50
    /// Max chars for memory context injected into system prompt (~750 tokens for most tokenizers).
    private let maxMemoryChars = 3000
    /// Days for age-based relevance decay (half-life).
    private let ageDecayHalfLife: Double = 30

    /// Embedding service for semantic similarity.
    private let embeddings = EmbeddingService.shared
    /// Cosine similarity threshold for considering two facts duplicates.
    private let embeddingDedupThreshold: Float = 0.85
    /// Last user query text — used for semantic fact selection in buildMemoryContext.
    private var lastQueryText: String = ""
    /// Cached embedding for last query.
    private var lastQueryEmbedding: [Double]? = nil

    // MARK: - Init

    private init() {
        // isEnabled is already initialized via AppDefaults in the property declaration
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        updateEntryCount()
    }

    // MARK: - Fact Extraction

    /// Store facts directly (called by UpdateMemoryTool).
    /// Deduplicates against existing facts and resolves conflicts (replaces old contradictory facts).
    func storeFacts(_ facts: [String]) async {
        guard isEnabled, let context = modelContext else { return }

        for fact in facts {
            let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 10 else { continue }

            // Fast text-based pre-filter
            if isDuplicateText(trimmed) { continue }

            // Embedding-based semantic check (deeper check)
            if isDuplicateEmbedding(trimmed) { continue }

            // Check for conflicting fact (same subject, different statement)
            if let conflictID = findConflictingFact(trimmed) {
                // Replace the old conflicting fact with the new one
                if let oldEntry = factsCache.first(where: { $0.id == conflictID }) {
                    context.delete(oldEntry)
                    factsCache.removeAll { $0.id == conflictID }
                    wordSetsCache.removeValue(forKey: conflictID)
                    normalizedCache.removeValue(forKey: conflictID)
                }
            }

            let entry = MemoryEntry(
                text: trimmed,
                conversationID: currentConversationID ?? UUID()
            )
            context.insert(entry)
            factsCache.append(entry)
            wordSetsCache[entry.id] = wordSet(from: trimmed)
            normalizedCache[entry.id] = normalizeText(trimmed)

            // Pre-compute embedding in background (non-blocking for store speed)
            if embeddings.isAvailable {
                Task { @MainActor [entry] in
                    _ = embeddings.embedding(for: entry.id, text: trimmed)
                }
            }
        }

        invalidateCaches()

        if factsCache.count > maxFacts * 2 {
            pruneOldest(keepCount: maxFacts)
        }

        do {
            try context.save()
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Save error: \(error)")
        }
    }

    /// Update the summary of the current conversation (called by UpdateMemoryTool).
    func updateConversationSummary(_ summary: String) async {
        guard let context = modelContext, let convID = currentConversationID else { return }
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == convID }
        )
        guard let conversation = try? context.fetch(descriptor).first else { return }
        conversation.summary = summary
        try? context.save()
        invalidateCaches()
    }

    /// Remove facts by exact text match (called by UpdateMemoryTool).
    /// The model must provide the exact fact text — substring matching is NOT used.
    func removeFacts(_ factsToRemove: [String]) async {
        guard let context = modelContext else { return }
        let toRemove = Set(factsToRemove.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        // Collect IDs to remove first — avoids mutating the array during iteration.
        var idsToRemove = Set<UUID>()
        for entry in factsCache {
            if toRemove.contains(entry.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
                idsToRemove.insert(entry.id)
            }
        }

        guard !idsToRemove.isEmpty else { return }

        for id in idsToRemove {
            if let entry = factsCache.first(where: { $0.id == id }) {
                context.delete(entry)
            }
        }
        factsCache.removeAll { idsToRemove.contains($0.id) }
        wordSetsCache = wordSetsCache.filter { !idsToRemove.contains($0.key) }
        normalizedCache = normalizedCache.filter { !idsToRemove.contains($0.key) }

        invalidateCaches()

        do {
            try context.save()
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Remove error: \(error)")
        }
    }

    /// Returns all currently stored facts as an array of strings.
    func allFactTexts() -> [String] {
        if !cacheLoaded { loadCache() }
        return factsCache.map { $0.text }
    }


    /// Set the current conversation query for semantic fact selection.
    /// Called by ChatViewModel before inference to pre-compute query embedding.
    /// The embedding is used in buildMemoryContext to rank facts by relevance.
    func setQueryContext(_ query: String) {
        lastQueryText = query
        lastQueryEmbedding = nil  // reset — will be lazily computed
        // Invalidate context cache since relevance ordering changed
        memoryContextCache = nil

        // Pre-compute query embedding in background
        if embeddings.isAvailable {
            Task { @MainActor [weak self, query] in
                self?.lastQueryEmbedding = self?.embeddings.embed(query)
            }
        }
    }
    // MARK: - Context Building

    /// Build memory context string for injection into system prompt.
    /// Results are cached until facts are modified — avoids re-sorting on every call.
    /// Facts are sorted by relevance score: blend of usage count and recency with age decay.
    func buildMemoryContext() -> String {
        guard isEnabled else { return "" }
        if !cacheLoaded { loadCache() }
        guard !factsCache.isEmpty else { return "" }

        if let cached = memoryContextCache {
            return cached
        }

        var context = "<memory>\n"
        // Sort by blended score: usage/recency + semantic similarity to query.
        // When embeddings are available AND query context is set, semantic relevance
        // dominates (0.7 weight); otherwise pure relevance score.
        let now = Date()
        let useSemantic = embeddings.isAvailable && lastQueryEmbedding != nil
        let queryVec = lastQueryEmbedding

        let sorted = factsCache.sorted { a, b in
            let scoreA = blendedScore(fact: a, now: now, useSemantic: useSemantic, queryVec: queryVec)
            let scoreB = blendedScore(fact: b, now: now, useSemantic: useSemantic, queryVec: queryVec)
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
        memoryContextCache = context

        // Increment usageCount for included facts (async save, non-blocking)
        if !includedFacts.isEmpty {
            Task { @MainActor [includedFacts] in
                guard let ctx = modelContext else { return }
                for fact in includedFacts {
                    fact.usageCount += 1
                }
                try? ctx.save()
            }
        }

        return context
    }

    /// Relevance score for context sorting.
    /// Combines usage frequency with recency using exponential decay.
    /// - A fact used 10 times yesterday scores higher than one used 10 times 3 months ago.
    /// - A fact never used (usageCount=0) still gets a small baseline from recency.
    private func relevanceScore(fact: MemoryEntry, now: Date) -> Double {
        let ageDays = max(0.0, now.timeIntervalSince(fact.timestamp)) / 86400.0
        let decay = exp(-ageDays / ageDecayHalfLife)
        // Base score of 1 ensures new facts get ranked even without usage.
        // usageCount amplifies frequently-referenced facts.
        let usageBoost = 1.0 + Double(fact.usageCount) * 0.5
        return usageBoost * decay
    }

    /// Blended score: relevance (usage count + recency) combined with semantic similarity.
    /// When embeddings are available, semantic relevance dominates (0.7 weight).
    private func blendedScore(fact: MemoryEntry, now: Date, useSemantic: Bool, queryVec: [Double]?) -> Double {
        let base = relevanceScore(fact: fact, now: now)
        guard useSemantic, let queryVec,
              let factVec = embeddings.embedding(for: fact.id, text: fact.text) else {
            return base
        }
        let semantic = Double(embeddings.cosineSimilarity(queryVec, factVec))
        return base * 0.3 + semantic * 0.7
    }

    /// Build the full system prompt with memory + conversation summary injected.
    /// Single source of truth — used by both ChatViewModel.refreshContextTracker
    /// and LiteRTLMProvider.buildConversation.
    /// Results are cached and invalidated when facts, summary, or base prompt change.
    func buildFullSystemPrompt(base: String, conversationID: UUID?) -> String {
        // Return cached result if inputs haven't changed
        if let cached = systemPromptCache,
           cached.base == base,
           cached.conversationID == conversationID {
            return cached.result
        }

        var fullSystem = base

        if isEnabled {
            fullSystem += "\n\nRemember important user facts via update_memory tool. Summarize long conversations via summary parameter."

            if let convID = conversationID,
               let context = modelContext {
                let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convID })
                if let summary = (try? context.fetch(descriptor).first?.summary), !summary.isEmpty {
                    fullSystem += "\n\n<conversation_summary>\n\(summary)\n</conversation_summary>"
                }
            }

            let memCtx = buildMemoryContext()
            if !memCtx.isEmpty {
                fullSystem += "\n\n" + memCtx
            }
        }

        systemPromptCache = (base: base, conversationID: conversationID, result: fullSystem)
        return fullSystem
    }

    // MARK: - Maintenance

    /// All stored facts, sorted by date.
    var allFacts: [MemoryEntry] {
        if !cacheLoaded { loadCache() }
        return factsCache.sorted { $0.timestamp > $1.timestamp }
    }

    /// Delete a single fact by ID.
    func deleteFact(_ entry: MemoryEntry) {
        guard let context = modelContext else { return }
        context.delete(entry)
        factsCache.removeAll { $0.id == entry.id }
        wordSetsCache.removeValue(forKey: entry.id)
        normalizedCache.removeValue(forKey: entry.id)
        invalidateCaches()
        do {
            try context.save()
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Delete error: \(error)")
        }
    }

    func clearAll() {
        guard let context = modelContext else { return }
        do {
            try context.delete(model: MemoryEntry.self)
            try context.save()
            factsCache.removeAll()
            wordSetsCache.removeAll()
            normalizedCache.removeAll()
            cacheLoaded = false
            invalidateCaches()
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Clear error: \(error)")
        }
    }

    func pruneOldEntries(olderThan days: Int = 90) {
        guard let context = modelContext else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let descriptor = FetchDescriptor<MemoryEntry>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        do {
            let old = try context.fetch(descriptor)
            for entry in old { context.delete(entry) }
            try context.save()
            factsCache.removeAll()
            wordSetsCache.removeAll()
            normalizedCache.removeAll()
            cacheLoaded = false
            invalidateCaches()
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Prune error: \(error)")
        }
    }

    // MARK: - Private: Deduplication

    /// Check if a fact is too similar to any existing fact.
    /// Uses two-stage detection:
    /// 1. Jaccard similarity on word sets (fast, catches rephrasings)
    /// 2. Normalized text comparison (catches near-identical text)
    /// Threshold adapts to fact length — shorter facts need higher similarity to be duplicates.
    private func isDuplicateText(_ newFact: String) -> Bool {
        let newWords = wordSet(from: newFact)
        guard !newWords.isEmpty else { return true }

        let newNormalized = normalizeText(newFact)
        let wordCount = newWords.count

        // Stricter threshold for short facts (3-5 words can overlap by chance)
        let jaccardThreshold: Float = wordCount <= 5 ? 0.75 : 0.60

        for existing in factsCache {
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

    /// Async embedding-based duplicate check.
    /// Computes embedding for the new fact and checks cosine similarity against all cached facts.
    /// Falls back to false (not a duplicate) if embeddings are unavailable or computation fails.
    private func isDuplicateEmbedding(_ newFact: String) -> Bool {
        guard embeddings.isAvailable else { return false }

        guard let newVec = embeddings.embed(newFact) else { return false }

        for existing in factsCache {
            guard let existingVec = embeddings.embedding(for: existing.id, text: existing.text) else {
                continue
            }
            let sim = embeddings.cosineSimilarity(newVec, existingVec)
            if sim > embeddingDedupThreshold {
                return true
            }
        }
        return false
    }

    /// Find an existing fact that conflicts with the new one.
    /// Conflict = same subject entity but different/contradictory predicate.
    /// Heuristic: extract the "subject" (first noun phrase or first 2-3 words)
    /// and check if an existing fact shares the subject but differs in the rest.
    private func findConflictingFact(_ newFact: String) -> UUID? {
        // Extract subject: first few words (up to first significant word boundary)
        let newSubject = extractSubject(newFact)
        guard newSubject.count >= 2 else { return nil }

        for existing in factsCache {
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

    /// Extract the "subject" of a fact — the first 2-3 content words.
    /// Handles patterns like "User's name is X" → ["user", "name"]
    /// or "User lives in City" → ["user", "lives"]
    private func extractSubject(_ text: String) -> [String] {
        let stopWords: Set<String> = ["a", "an", "the", "is", "are", "was", "were",
                                       "has", "have", "had", "in", "on", "at", "to",
                                       "for", "of", "with", "by", "from", "as", "or",
                                       "and", "but", "not", "no", "yes", "very", "just",
                                       "that", "this", "it", "its", "he", "she", "they",
                                       "his", "her", "their", "my", "your", "our"]
        let words = text.lowercased()
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return Array(words.prefix(3))
    }

    // MARK: - Private: Pruning

    /// Remove oldest, least-used facts to stay within budget.
    /// Saves changes to SwiftData.
    private func pruneOldest(keepCount: Int) {
        guard let context = modelContext, factsCache.count > keepCount else { return }

        let sorted = factsCache.sorted { a, b in
            if a.usageCount != b.usageCount { return a.usageCount < b.usageCount }
            return a.timestamp < b.timestamp
        }

        let toRemove = sorted.prefix(sorted.count - keepCount)
        let removeIDs = Set(toRemove.map { $0.id })

        for entry in toRemove {
            context.delete(entry)
        }
        factsCache.removeAll { removeIDs.contains($0.id) }
        for id in removeIDs {
            wordSetsCache.removeValue(forKey: id)
            normalizedCache.removeValue(forKey: id)
        }

        try? context.save()
    }

    // MARK: - Private: Helpers

    /// Extract lowercase word set from text for similarity comparison.
    private func wordSet(from text: String) -> Set<String> {
        let words = text.lowercased()
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        return Set(words)
    }

    /// Normalize text for comparison: lowercase, strip punctuation, normalize whitespace.
    private func normalizeText(_ text: String) -> String {
        let lowercased = text.lowercased()
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
        let cleaned = String(lowercased.unicodeScalars.filter { allowed.contains($0) })
        let words = cleaned.split(separator: " ").map(String.init)
        return words.joined(separator: " ")
    }

    private func loadCache() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<MemoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        factsCache = (try? context.fetch(descriptor)) ?? []
        // Pre-compute word sets and normalized text for all cached facts
        wordSetsCache.removeAll(keepingCapacity: true)
        normalizedCache.removeAll(keepingCapacity: true)
        for entry in factsCache {
            wordSetsCache[entry.id] = wordSet(from: entry.text)
            normalizedCache[entry.id] = normalizeText(entry.text)
        }
        cacheLoaded = true
    }

    /// Invalidate all caches that depend on memory facts.
    func invalidateCaches() {
        memoryContextCache = nil
        systemPromptCache = nil
    }

    private func updateEntryCount() {
        guard let context = modelContext else { return }
        totalEntries = (try? context.fetchCount(FetchDescriptor<MemoryEntry>())) ?? 0
    }
}
