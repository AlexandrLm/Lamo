import Foundation
import SwiftData
import Combine
import os

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
    private var memoryContextCache: (query: String?, result: String)?
    private var wordSetsCache: [UUID: Set<String>] = [:]
    private var normalizedCache: [UUID: String] = [:]
    private var systemPromptCache: (base: String, conversationID: UUID?, result: String)?

    private let maxFacts = 50
    private let maxMemoryChars = 3000
    private let ageDecayHalfLife: Double = 30

    private let contextBuilder = MemoryContextBuilder(maxFacts: 50, maxMemoryChars: 3000, ageDecayHalfLife: 30)

    private let embeddings = EmbeddingService.shared
    private let embeddingDedupThreshold: Float = 0.96
    private static let noiseMarkers = [
        "asked about", "asked a question", "said hello", "said hi",
        "greeted", "started a conversation", "temporary", "one-off",
        "test message", "hello world"
    ]

    // MARK: - Init

    init() {
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        invalidateCaches()
        updateEntryCount()
    }

    // MARK: - Fact Extraction

    @discardableResult
    func storeFacts(_ facts: [String], conversationID: UUID? = nil) async -> (stored: [String], skipped: [String]) {
        guard isEnabled, let context = modelContext else { return ([], []) }

        var stored: [String] = []
        var skipped: [String] = []

        for fact in facts {
            let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 8 else { skipped.append(trimmed); continue }
            let lowered = trimmed.lowercased()
            var isNoise = false
            for marker in Self.noiseMarkers {
                if lowered.contains(marker) { isNoise = true; break }
            }
            if isNoise { skipped.append(trimmed); continue }

            if MemoryDeduplicator.isDuplicateText(trimmed, existingFacts: factsCache, wordSetsCache: &wordSetsCache, normalizedCache: &normalizedCache) {
                skipped.append(trimmed)
                continue
            }

            if let conflictID = MemoryDeduplicator.findConflictingFact(trimmed, existingFacts: factsCache, wordSetsCache: wordSetsCache, normalizedCache: normalizedCache) {
                if let oldEntry = factsCache.first(where: { $0.id == conflictID }) {
                    context.delete(oldEntry)
                    factsCache.removeAll { $0.id == conflictID }
                    wordSetsCache.removeValue(forKey: conflictID)
                    normalizedCache.removeValue(forKey: conflictID)
                    embeddings.remove(ids: [conflictID])
                }
            } else if MemoryDeduplicator.isDuplicateEmbedding(trimmed, existingFacts: factsCache, embeddingService: embeddings, threshold: embeddingDedupThreshold) {
                skipped.append(trimmed)
                continue
            }

            let entry = MemoryEntry(
                text: trimmed,
                conversationID: conversationID ?? UUID()
            )
            context.insert(entry)
            factsCache.append(entry)
            wordSetsCache[entry.id] = MemoryDeduplicator.wordSet(from: trimmed)
            normalizedCache[entry.id] = MemoryDeduplicator.normalizeText(trimmed)

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

    func updateConversationSummary(_ summary: String, conversationID: UUID? = nil) async {
        guard let context = modelContext, let convID = conversationID else { return }
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == convID }
        )
        guard let conversation = try? context.fetch(descriptor).first else { return }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if conversation.summary.isEmpty {
            conversation.summary = String(trimmed.prefix(Conversation.maxSummaryChars))
        } else if !trimmed.contains(conversation.summary) && !conversation.summary.contains(trimmed) {
            let chained = conversation.summary + "\n" + trimmed
            conversation.summary = String(chained.suffix(Conversation.maxSummaryChars))
        } else if trimmed.count > conversation.summary.count {
            conversation.summary = String(trimmed.prefix(Conversation.maxSummaryChars))
        } else {
            return
        }
        try? context.save()
        invalidateCaches()
    }

    @discardableResult
    func removeFacts(_ factsToRemove: [String]) async -> (removed: [String], notFound: [String]) {
        guard let context = modelContext else { return ([], factsToRemove) }
        if !cacheLoaded { loadCache() }

        var remainingInputs = factsToRemove
        var idsToRemove = Set<UUID>()
        var removedTexts: [String] = []

        for input in factsToRemove {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let indexText = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
                ? String(trimmed.dropFirst().dropLast()) : trimmed
            if let idx = Int(indexText.trimmingCharacters(in: .whitespaces)),
               idx >= 0, idx < factsCache.count {
                let sorted = factsCache.sorted { $0.timestamp > $1.timestamp }
                if idx < sorted.count {
                    let entry = sorted[idx]
                    if !idsToRemove.contains(entry.id) {
                        idsToRemove.insert(entry.id)
                        removedTexts.append(entry.text)
                        remainingInputs.removeAll { $0 == input }
                    }
                    continue
                }
            }
            let normalizedInput = MemoryDeduplicator.normalizeText(trimmed)
            var matched = false
            for entry in factsCache where !idsToRemove.contains(entry.id) {
                let normalizedStored = normalizedCache[entry.id] ?? MemoryDeduplicator.normalizeText(entry.text)
                if normalizedStored == normalizedInput {
                    idsToRemove.insert(entry.id)
                    removedTexts.append(entry.text)
                    matched = true
                    break
                }
            }
            if !matched {
                for entry in factsCache where !idsToRemove.contains(entry.id) {
                    let normalizedStored = normalizedCache[entry.id] ?? MemoryDeduplicator.normalizeText(entry.text)
                    guard normalizedStored.count > 10 && normalizedInput.count > 10 else { continue }
                    if normalizedStored.contains(normalizedInput) || normalizedInput.contains(normalizedStored) {
                        let ratio = Double(min(normalizedStored.count, normalizedInput.count))
                            / Double(max(normalizedStored.count, normalizedInput.count))
                        if ratio > 0.7 {
                            idsToRemove.insert(entry.id)
                            removedTexts.append(entry.text)
                            matched = true
                            break
                        }
                    }
                }
            }
            if matched {
                remainingInputs.removeAll { $0 == input }
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
        embeddings.remove(ids: Array(idsToRemove))
        return (removedTexts, remainingInputs)
    }

    /// Returns all currently stored facts as an array of strings.
    func allFactTexts() -> [String] {
        if !cacheLoaded { loadCache() }
        return factsCache.map { $0.text }
    }

    // MARK: - Context Building

    func buildMemoryContext(for query: String? = nil) -> String {
        guard isEnabled else { return "" }
        if !cacheLoaded { loadCache() }
        guard !factsCache.isEmpty else { return "" }

        if let cached = memoryContextCache, cached.query == query {
            return cached.result
        }

        let queryVecs: [EmbeddedText]
        if let query, embeddings.isAvailable {
            queryVecs = embeddings.embedAll(query)
        } else {
            queryVecs = []
        }

        let result = contextBuilder.buildContext(
            factsCache: factsCache,
            embeddingService: embeddings,
            lastQueryText: query ?? "",
            lastQueryEmbedding: queryVecs.first,
            lastQueryEmbeddings: queryVecs
        )

        memoryContextCache = (query: query, result: result.context)

        if !result.includedFacts.isEmpty, query != nil {
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

    var allFacts: [MemoryEntry] {
        if !cacheLoaded { loadCache() }
        return factsCache.sorted { $0.timestamp > $1.timestamp }
    }

    func deleteFact(_ entry: MemoryEntry) {
        guard let context = modelContext else { return }
        context.delete(entry)
        factsCache.removeAll { $0.id == entry.id }
        wordSetsCache.removeValue(forKey: entry.id)
        normalizedCache.removeValue(forKey: entry.id)
        embeddings.remove(ids: [entry.id])
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
            embeddings.removeAll()
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
            let protectedIDs = Set(factsCache.filter { $0.usageCount >= 3 }.map { $0.id })
            var removedIDs: [UUID] = []
            for entry in old where !protectedIDs.contains(entry.id) {
                context.delete(entry)
                removedIDs.append(entry.id)
            }
            try context.save()
            factsCache.removeAll()
            wordSetsCache.removeAll()
            normalizedCache.removeAll()
            embeddings.remove(ids: removedIDs)
            cacheLoaded = false
            invalidateCaches()
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Prune error: \(error)")
        }
    }

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
        embeddings.remove(ids: Array(removeIDs))

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
