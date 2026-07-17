import Foundation
import SwiftData
import Combine
import os

/// Semantic memory that stores facts about the user.
///
/// Architecture (like ChatGPT):
/// 1. During LLM response → model calls update_memory tool with facts
/// 2. Facts stored as plain text in SwiftData
/// 3. Before each LLM call → ALL facts injected into system prompt
///
/// No embedding model needed — the LLM extracts facts via function calling.
/// No vector search needed — all facts fit in the system prompt.
@MainActor
final class MemoryService: ObservableObject {
    static let shared = MemoryService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "memoryEnabled")
        }
    }

    @Published var totalEntries: Int = 0

    private(set) var modelContext: ModelContext?
    private var factsCache: [MemoryEntry] = []
    private var cacheLoaded = false
    /// Cached result of buildMemoryContext() — invalidated on any fact change.
    private var memoryContextCache: String?

    /// Current conversation ID — set by ChatViewModel before each message.
    /// Used by UpdateMemoryTool to update conversation summary.
    var currentConversationID: UUID?

    /// Max facts to inject into system prompt.
    /// 50 facts × ~60 chars = ~3000 chars ≈ 750 tokens. Fits easily.
    private let maxFacts = 50
    /// Max characters for the memory block in system prompt.
    private let maxMemoryChars = 3000

    // MARK: - Init

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "memoryEnabled") as? Bool ?? true
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        updateEntryCount()
    }

    // MARK: - Fact Extraction

    /// Store facts directly (called by UpdateMemoryTool).
    func storeFacts(_ facts: [String]) async {
        guard isEnabled, let context = modelContext else { return }

        for fact in facts {
            let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 10, !isDuplicate(trimmed) else { continue }

            let entry = MemoryEntry(
                text: trimmed,
                conversationID: UUID()
            )
            context.insert(entry)
            factsCache.append(entry)
        }

        memoryContextCache = nil

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
    }

    /// Remove facts that match the given strings (called by UpdateMemoryTool).
    func removeFacts(_ factsToRemove: [String]) async {
        guard let context = modelContext else { return }
        let toRemove = factsToRemove.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

        var didRemove = false
        for entry in factsCache {
            let entryText = entry.text.lowercased()
            for removeText in toRemove {
                if entryText.contains(removeText) || removeText.contains(entryText) {
                    context.delete(entry)
                    factsCache.removeAll { $0.id == entry.id }
                    didRemove = true
                    break
                }
            }
        }

        if didRemove { memoryContextCache = nil }

        do {
            try context.save()
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Remove error: \(error)")
        }
    }

    // MARK: - Context Building

    /// Build memory context string for injection into system prompt.
    /// Results are cached until facts are modified — avoids re-sorting on every call.
    func buildMemoryContext() -> String {
        guard isEnabled else { return "" }
        if !cacheLoaded { loadCache() }
        guard !factsCache.isEmpty else { return "" }

        if let cached = memoryContextCache {
            return cached
        }

        var context = "<memory>\n"
        var totalChars = 0

        // Most recent + most used facts first
        let sorted = factsCache.sorted { a, b in
            if a.usageCount != b.usageCount { return a.usageCount > b.usageCount }
            return a.timestamp > b.timestamp
        }

        for fact in sorted.prefix(maxFacts) {
            let line = "• \(fact.text)\n"
            if totalChars + line.count > maxMemoryChars { break }
            context += line
            totalChars += line.count
        }

        context += "</memory>"
        memoryContextCache = context
        return context
    }

    /// Build the full system prompt with memory + conversation summary injected.
    /// Single source of truth — used by both ChatViewModel.refreshContextTracker
    /// and LiteRTLMProvider.buildConversation.
    func buildFullSystemPrompt(base: String, conversationID: UUID?) -> String {
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
        memoryContextCache = nil
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
            cacheLoaded = false
            memoryContextCache = nil
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
            cacheLoaded = false
            memoryContextCache = nil
            updateEntryCount()
        } catch {
            LamoLogger.memory.error("Prune error: \(error)")
        }
    }

    // MARK: - Private

    /// Check if a fact is too similar to any existing fact.
    private func isDuplicate(_ newFact: String) -> Bool {
        let newWords = Set(newFact.lowercased().split(separator: " ").map(String.init))

        for existing in factsCache {
            let existingWords = Set(existing.text.lowercased().split(separator: " ").map(String.init))
            let intersection = newWords.intersection(existingWords)
            let union = newWords.union(existingWords)

            guard !union.isEmpty else { continue }
            let similarity = Float(intersection.count) / Float(union.count)
            if similarity > 0.6 { return true }
        }

        return false
    }

    /// Remove oldest, least-used facts to stay within budget.
    private func pruneOldest(keepCount: Int) {
        guard let context = modelContext else { return }

        let sorted = factsCache.sorted { a, b in
            if a.usageCount != b.usageCount { return a.usageCount < b.usageCount }
            return a.timestamp < b.timestamp
        }

        let toRemove = sorted.prefix(sorted.count - keepCount)
        for entry in toRemove {
            context.delete(entry)
            factsCache.removeAll { $0.id == entry.id }
        }
    }

    private func loadCache() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<MemoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        factsCache = (try? context.fetch(descriptor)) ?? []
        cacheLoaded = true
    }

    private func updateEntryCount() {
        guard let context = modelContext else { return }
        totalEntries = (try? context.fetchCount(FetchDescriptor<MemoryEntry>())) ?? 0
    }
}
