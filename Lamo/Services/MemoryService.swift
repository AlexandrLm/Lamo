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
    /// Keyed by query (nil = generic ranking). The query path is cached too:
    /// without it, embedding + ranking re-runs up to 4× per response
    /// (tracker build + provider inference), and each run re-bumps usageCount.
    private var memoryContextCache: (query: String?, result: String)?
    /// Cached word sets for duplicate detection — computed on load, updated on mutation.
    private var wordSetsCache: [UUID: Set<String>] = [:]
    /// Cached normalized text for conflict detection.
    private var normalizedCache: [UUID: String] = [:]
    /// Cache for the full system prompt including memory — invalidated on fact/summary change.
    private var systemPromptCache: (base: String, conversationID: UUID?, result: String)?

    /// Max facts to inject into system prompt.
    private let maxFacts = 50
    /// Max chars for memory context injected into system prompt (~750 tokens for most tokenizers).
    private let maxMemoryChars = 3000
    /// Days for age-based relevance decay (half-life).
    private let ageDecayHalfLife: Double = 30

    /// Context builder for ranking and formatting memory facts.
    private let contextBuilder = MemoryContextBuilder(maxFacts: 50, maxMemoryChars: 3000, ageDecayHalfLife: 30)

    /// Embedding service for semantic similarity.
    private let embeddings = EmbeddingService.shared
    /// Cosine similarity threshold for considering two facts duplicates.
    ///
    /// Calibrated against the on-device NLContextualEmbedding vectors (word-pooled,
    /// lowercased): genuine rephrasings ("user name is Alice Johnson" vs "... Bob
    /// Smith" aside) cluster at 0.96–0.99, while structurally similar but distinct
    /// facts land at 0.85–0.95. A threshold of 0.96 merges rephrasings without
    /// dropping distinct facts — e.g. a name change must be replaced, not treated
    /// as a duplicate.
    private let embeddingDedupThreshold: Float = 0.96

    // MARK: - Init

    /// Internal so tests can construct isolated instances (per-test containers)
    /// instead of all racing on the shared singleton's model context.
    init() {
        // isEnabled is already initialized via AppDefaults in the property declaration
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        // A different store means different facts — drop all caches so the next
        // build reads from the new context (test isolation, engine reload).
        invalidateCaches()
        updateEntryCount()
    }

    // MARK: - Fact Extraction

    /// Store facts directly (called by UpdateMemoryTool).
    /// Deduplicates against existing facts and resolves conflicts (replaces old contradictory facts).
    /// `conversationID` records provenance; nil falls back to a fresh UUID.
    /// Returns what actually happened per fact so the tool can report back to the model.
    @discardableResult
    func storeFacts(_ facts: [String], conversationID: UUID? = nil) async -> (stored: [String], skipped: [String]) {
        guard isEnabled, let context = modelContext else { return ([], []) }

        var stored: [String] = []
        var skipped: [String] = []

        for fact in facts {
            let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 10 else { skipped.append(trimmed); continue }

            // Fast text-based pre-filter
            if MemoryDeduplicator.isDuplicateText(trimmed, existingFacts: factsCache, wordSetsCache: &wordSetsCache, normalizedCache: &normalizedCache) {
                skipped.append(trimmed)
                continue
            }

            // Embedding-based semantic check (deeper check)
            if MemoryDeduplicator.isDuplicateEmbedding(trimmed, existingFacts: factsCache, embeddingService: embeddings, threshold: embeddingDedupThreshold) {
                skipped.append(trimmed)
                continue
            }

            // Check for conflicting fact (same subject, different statement)
            if let conflictID = MemoryDeduplicator.findConflictingFact(trimmed, existingFacts: factsCache, wordSetsCache: wordSetsCache, normalizedCache: normalizedCache) {
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
                conversationID: conversationID ?? UUID()
            )
            context.insert(entry)
            factsCache.append(entry)
            wordSetsCache[entry.id] = MemoryDeduplicator.wordSet(from: trimmed)
            normalizedCache[entry.id] = MemoryDeduplicator.normalizeText(trimmed)

            // Pre-compute embedding in background (non-blocking for store speed).
            // Capture values only — the model instance may be destroyed if the
            // context is reset (test teardown, memory pressure) before the task runs.
            if embeddings.isAvailable {
                let id = entry.id
                Task { @MainActor in
                    _ = embeddings.embedding(for: id, text: trimmed)
                }
            }
            stored.append(trimmed)
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
        return (stored, skipped)
    }

    /// Update the summary of a conversation (called by UpdateMemoryTool / ConversationBuilder).
    func updateConversationSummary(_ summary: String, conversationID: UUID? = nil) async {
        guard let context = modelContext, let convID = conversationID else { return }
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
    /// Returns the canonical stored text of removed facts and the inputs that matched nothing,
    /// so the tool can tell the model which forgets actually happened.
    @discardableResult
    func removeFacts(_ factsToRemove: [String]) async -> (removed: [String], notFound: [String]) {
        guard let context = modelContext else { return ([], factsToRemove) }
        var remaining = Set(factsToRemove.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })

        // Collect IDs to remove first — avoids mutating the array during iteration.
        var idsToRemove = Set<UUID>()
        var removedTexts: [String] = []
        for entry in factsCache {
            let normalized = entry.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.contains(normalized) {
                idsToRemove.insert(entry.id)
                removedTexts.append(entry.text)
                remaining.remove(normalized)
            }
        }

        guard !idsToRemove.isEmpty else { return ([], factsToRemove) }

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
        return (removedTexts, factsToRemove.filter {
            remaining.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        })
    }

    /// Returns all currently stored facts as an array of strings.
    func allFactTexts() -> [String] {
        if !cacheLoaded { loadCache() }
        return factsCache.map { $0.text }
    }

    // MARK: - Context Building

    /// Build memory context string for injection into system prompt.
    ///
    /// When `query` is provided (the user's latest message), uses true RAG semantic retrieval:
    /// 1. Embeds the query
    /// 2. Ranks facts by blended score (semantic similarity 70% + usage/recency 30%)
    /// 3. Returns only facts relevant to the current query
    ///
    /// When `query` is nil (context tracker, settings changes), falls back to
    /// ranking by usage count + recency only. Result is cached.
    ///
    /// Delegates ranking and formatting to MemoryContextBuilder.
    func buildMemoryContext(for query: String? = nil) -> String {
        guard isEnabled else { return "" }
        if !cacheLoaded { loadCache() }
        guard !factsCache.isEmpty else { return "" }

        // Query-keyed cache: the same query resolves to the same ranking within a
        // turn. Covers both the nil-query (context tracker) and RAG paths.
        if let cached = memoryContextCache, cached.query == query {
            return cached.result
        }

        // Compute query embedding for semantic retrieval
        let queryVec: EmbeddedText?
        if let query, embeddings.isAvailable {
            queryVec = embeddings.embed(query)
        } else {
            queryVec = nil
        }

        let result = contextBuilder.buildContext(
            factsCache: factsCache,
            embeddingService: embeddings,
            lastQueryText: query ?? "",
            lastQueryEmbedding: queryVec
        )

        memoryContextCache = (query: query, result: result.context)

        // Increment usageCount for included facts (async save, non-blocking)
        if !result.includedFacts.isEmpty {
            Task { @MainActor [includedFacts = result.includedFacts] in
                guard let ctx = modelContext else { return }
                for fact in includedFacts {
                    fact.usageCount += 1
                }
                try? ctx.save()
            }
        }

        return result.context
    }
    /// Build the full system prompt with memory + conversation summary injected.
    /// Single source of truth — used by both ChatViewModel.refreshContextTracker
    /// and LiteRTLMProvider.buildConversation.
    /// Results are cached and invalidated when facts, summary, or base prompt change.
    /// - Parameter userQuery: The user's latest message for semantic memory retrieval.
    ///   Pass nil when building prompt for context tracking (e.g., refreshContextTracker).
    func buildFullSystemPrompt(base: String, conversationID: UUID?, userQuery: String? = nil) -> String {
        // Return cached result if inputs haven't changed and we're not using query-specific retrieval
        if userQuery == nil,
           let cached = systemPromptCache,
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

            let memCtx = buildMemoryContext(for: userQuery)
            if !memCtx.isEmpty {
                fullSystem += "\n\n" + memCtx
            }
        }

        if userQuery == nil {
            systemPromptCache = (base: base, conversationID: conversationID, result: fullSystem)
        }
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
            wordSetsCache[entry.id] = MemoryDeduplicator.wordSet(from: entry.text)
            normalizedCache[entry.id] = MemoryDeduplicator.normalizeText(entry.text)
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
