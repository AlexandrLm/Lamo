import Foundation
import SwiftData
import Combine

/// Semantic memory that extracts and stores facts about the user.
///
/// Architecture (like ChatGPT):
/// 1. After each LLM response → extract key facts via a quick LLM call
/// 2. Store facts as plain text strings in SwiftData
/// 3. Before each LLM call → inject ALL facts into system prompt
///
/// No embedding model needed — the LLM itself extracts facts.
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

    private var modelContext: ModelContext?
    private var factsCache: [MemoryEntry] = []
    private var cacheLoaded = false

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

    /// Extract facts from a conversation turn and store them.
    /// Uses the LLM itself — no separate embedding model needed.
    ///
    /// - Parameters:
    ///   - userMessage: What the user said
    ///   - assistantResponse: What the assistant replied
    ///   - conversationID: Current conversation ID
    ///   - provider: LLM provider to use for extraction
    func extractAndStore(
        userMessage: String,
        assistantResponse: String,
        conversationID: UUID,
        provider: any LLMProvider
    ) async {
        guard isEnabled, let context = modelContext else { return }

        // Build extraction prompt
        let existingFacts = factsCache.map { "• \($0.text)" }.joined(separator: "\n")

        let extractionPrompt = """
        Analyze this conversation and extract important facts about the user that would be useful for future conversations.

        Rules:
        - Extract ONLY facts about the user (preferences, personal info, work, projects, dates)
        - Each fact must be one short sentence starting with "•"
        - Do NOT extract facts already listed below
        - Do NOT extract general knowledge or assistant's responses
        - If nothing worth remembering, respond with exactly: NONE

        Already known facts:
        \(existingFacts.isEmpty ? "(none)" : existingFacts)

        Conversation:
        User: \(userMessage)
        Assistant: \(assistantResponse.prefix(500))

        Extracted facts:
        """

        // Run extraction via LLM (quick, ~1-2 sec)
        let chatMessages = [ChatMessage(role: .user, content: extractionPrompt)]
        var result = ""

        for await token in provider.streamResponse(messages: chatMessages) {
            switch token {
            case .delta(let text): result += text
            case .done: break
            case .error: return
            case .thinkingDelta: break
            }
        }

        // Parse facts from response
        let facts = parseFacts(from: result)

        // Store new facts
        for fact in facts {
            // Deduplicate — skip if very similar to existing
            if !isDuplicate(fact) {
                let entry = MemoryEntry(
                    text: fact,
                    conversationID: conversationID
                )
                context.insert(entry)
                factsCache.append(entry)
            }
        }

        // Enforce max limit — remove oldest facts if over budget
        if factsCache.count > maxFacts * 2 {
            pruneOldest(keepCount: maxFacts)
        }

        do {
            try context.save()
            updateEntryCount()
        } catch {
            print("[Memory] Save error: \(error)")
        }
    }

    // MARK: - Context Building

    /// Build memory context string for injection into system prompt.
    func buildMemoryContext() -> String {
        guard isEnabled else { return "" }
        if !cacheLoaded { loadCache() }
        guard !factsCache.isEmpty else { return "" }

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
            fact.usageCount += 1
        }

        context += "</memory>"
        return context
    }

    // MARK: - Maintenance

    func clearAll() {
        guard let context = modelContext else { return }
        do {
            try context.delete(model: MemoryEntry.self)
            try context.save()
            factsCache.removeAll()
            cacheLoaded = false
            updateEntryCount()
        } catch {
            print("[Memory] Clear error: \(error)")
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
            updateEntryCount()
        } catch {
            print("[Memory] Prune error: \(error)")
        }
    }

    // MARK: - Private

    /// Parse facts from LLM response. Expected format: "• fact\n• fact\n..."
    private func parseFacts(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var facts: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and "NONE" response
            guard !trimmed.isEmpty,
                  trimmed.uppercased() != "NONE",
                  !trimmed.lowercased().contains("none") else { continue }

            // Extract fact after bullet point
            var fact = trimmed
            if fact.hasPrefix("•") {
                fact = String(fact.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if fact.hasPrefix("- ") {
                fact = String(fact.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if fact.hasPrefix("* ") {
                fact = String(fact.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }

            // Validate — must be a real fact, not garbage
            guard fact.count >= 10, fact.count <= 200 else { continue }

            facts.append(fact)
        }

        return facts
    }

    /// Check if a fact is too similar to any existing fact.
    private func isDuplicate(_ newFact: String) -> Bool {
        let newWords = Set(newFact.lowercased().split(separator: " ").map(String.init))

        for existing in factsCache {
            let existingWords = Set(existing.text.lowercased().split(separator: " ").map(String.init))
            let intersection = newWords.intersection(existingWords)
            let union = newWords.union(existingWords)

            // Jaccard similarity > 0.6 = duplicate
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
