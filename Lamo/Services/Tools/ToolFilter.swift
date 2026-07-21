import Foundation

// MARK: - Tool Filter

/// Reduces KV-cache overhead by selecting only relevant tools based on the user's query.
/// Two-tier approach: fast keyword matching + optional semantic embedding similarity.
///
/// Keyword matching always runs first (sub-millisecond). If EmbeddingService is available
/// and the query is long enough to produce meaningful embeddings, semantic similarity
/// boosts relevant categories and penalizes noise.
///
/// Savings: with 18 tools, filtering typically keeps 5-8 relevant ones,
/// reducing tool schema overhead from ~1800 to ~600 tokens.
enum ToolFilter {

    /// Categories for tool grouping. Used for both filtering and system prompt.
    enum Category: String, CaseIterable {
        case core          // reserved for future always-on tools (currently empty)
        case knowledge     // web search, wikipedia, fetch
        case productivity  // calendar, contacts, notes, reminders
        case system        // device, location, weather, shortcuts
        case health        // health data
        case code          // code sandbox, calculator
    }

    /// Maps tool name → categories. Tools can belong to multiple categories.
    private static let toolCategories: [String: Set<Category>] = [
        "calculator":             [.code],

        "web_search":             [.knowledge],
        "wikipedia":              [.knowledge],
        "fetch_url":              [.knowledge],

        "calendar":               [.productivity],
        "contacts":               [.productivity],
        "update_memory":          [.productivity],

        "get_location":           [.system],
        "weather":                [.system],
        "shortcuts":              [.system],

        "health":                 [.health],
    ]

    /// Keywords that trigger each category (lowercased). Matched against the user's query.
    private static let categoryKeywords: [Category: [String]] = [
        .knowledge: [
            "search", "find", "news", "article", "wiki", "look up", "research",
            "what is", "who is", "when did", "latest", "current", "today news",
            "поиск", "найди", "новости", "статья", "узнай", "что такое", "кто такой",
        ],
        .productivity: [
            "calendar", "schedule", "event", "meeting", "appointment", "remind",
            "contact", "phone", "email", "call", "message", "note", "memo",
            "календарь", "событие", "встреча", "контакт", "телефон", "заметка",
            "напомни", "звонок", "сообщение",
        ],
        .system: [
            "weather", "temperature", "forecast", "location", "where am i",
            "device", "battery", "storage", "shortcut", "open",
            "погода", "температура", "прогноз", "где я", "батарея",
        ],
        .health: [
            "health", "steps", "step", "heart", "pulse", "sleep", "weight",
            "calories", "workout", "fitness", "activity",
            "здоровье", "шаги", "шагов", "пульс", "сон", "вес", "калории",
        ],
        .code: [
            "code", "javascript", "calculate", "compute", "eval", "run",
            "script", "function", "program", "data", "analyze", "regex",
            "код", "посчитай", "вычисли", "скрипт", "функция", "данные",
        ],
    ]

    // MARK: - Keyword Filtering

    /// Determine which tool names to include based on the user's last message.
    /// Matches query keywords to categories. If no intent is detected, returns empty —
    /// the model chats fine without tools on vague/greeting queries.
    static func filter(toolNames: [String], query: String) -> [String] {
        let categories = activeCategories(from: query)

        // If no specific categories matched (only .core), return only core tools.
        if categories.count == 1 {
            let coreOnly = toolNames.filter { name in
                guard let cats = toolCategories[name] else { return false }
                return cats.contains(.core)
            }
            return coreOnly
        }

        // Filter: keep tools that belong to any active category
        let catSet = Set(categories)
        return toolNames.filter { name in
            guard let cats = toolCategories[name] else { return false }
            return !cats.isDisjoint(with: catSet)
        }
    }

    /// Extract active categories from query using keyword matching.
    private static func activeCategories(from query: String) -> [Category] {
        let lowerQuery = query.lowercased()
        var active = Set<Category>([.core])
        for (category, keywords) in categoryKeywords {
            if keywords.contains(where: { lowerQuery.contains($0) }) {
                active.insert(category)
            }
        }
        return Array(active)
    }

    // MARK: - Semantic Filtering (Embedding-based)

    /// Threshold below which embedding filtering falls back to keyword-only.
    private static let semanticMinQueryLength = 12

    /// Cached category embeddings — computed once per session from concatenated keywords.
    private static var cachedCategoryEmbeddings: [Category: [Double]] = [:]

    /// Compute and cache embeddings for all categories from their keyword sets.
    /// Called once when EmbeddingService becomes available.
    static func warmSemanticCache() {
        let embeddings = EmbeddingService.shared
        guard embeddings.isAvailable else { return }

        for (category, keywords) in categoryKeywords {
            let categoryText = keywords.joined(separator: " ")
            if let vec = embeddings.embed(categoryText) {
                cachedCategoryEmbeddings[category] = vec
            }
        }
    }

    /// Filter tools using semantic similarity to the query.
    /// Falls back to keyword-only if embeddings are unavailable or query is too short.
    static func filterSemantic(toolNames: [String], query: String) -> [String] {
        // Fast path: use keyword matching first
        let keywordResult = filter(toolNames: toolNames, query: query)

        // If no embedding service or query too short, return keyword results
        let embeddings = EmbeddingService.shared
        guard embeddings.isAvailable,
              query.count >= semanticMinQueryLength,
              !cachedCategoryEmbeddings.isEmpty else {
            return keywordResult
        }

        guard let queryVec = embeddings.embed(query) else {
            return keywordResult
        }

        // Compute similarity scores for each category
        var categoryScores: [Category: Float] = [:]
        for (category, catVec) in cachedCategoryEmbeddings {
            categoryScores[category] = embeddings.cosineSimilarity(queryVec, catVec)
        }

        // Threshold: categories with similarity > 0.3 are considered relevant
        let semanticCategories = categoryScores
            .filter { $0.value > 0.3 }
            .map(\.key)

        // Merge: union of keyword-matched and semantically-matched categories
        let keywordCategories = activeCategories(from: query)
        let mergedCategories = Set(keywordCategories + semanticCategories)

        // If nothing matched at all, return empty (model chats fine without tools)
        let nonCoreCategories = mergedCategories.filter { $0 != .core }
        if nonCoreCategories.isEmpty {
            let coreOnly = toolNames.filter { name in
                guard let cats = toolCategories[name] else { return false }
                return cats.contains(.core)
            }
            return coreOnly
        }

        return toolNames.filter { name in
            guard let cats = toolCategories[name] else { return false }
            return !cats.isDisjoint(with: mergedCategories)
        }
    }
}
