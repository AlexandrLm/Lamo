import Foundation

// MARK: - Tool Filter

/// Reduces KV-cache overhead by selecting only relevant tools based on the user's query.
/// Each tool is tagged with categories; the filter matches query keywords to categories.
///
/// Savings: with 18 tools, filtering typically keeps 5-8 relevant ones,
/// reducing tool schema overhead from ~1800 to ~600 tokens.
enum ToolFilter {

    /// Categories for tool grouping. Used for both filtering and system prompt.
    enum Category: String, CaseIterable {
        case core          // always included
        case knowledge     // web search, wikipedia, fetch
        case productivity  // calendar, contacts, notes, reminders
        case system        // device, location, weather, shortcuts
        case health        // health data
        case code          // code sandbox, calculator
    }

    /// Maps tool name → categories. Tools can belong to multiple categories.
    private static let toolCategories: [String: Set<Category>] = [
        "get_current_time":       [.core],
        "calculator":             [.code, .core],
        "think":                  [.core],

        "web_search":             [.knowledge],
        "wikipedia":              [.knowledge],
        "fetch_url":              [.knowledge],

        "calendar":               [.productivity],
        "calendar_availability":  [.productivity],
        "contacts":               [.productivity],
        "notes":                  [.productivity],
        "create_reminder":        [.productivity],
        "update_memory":          [.productivity],

        "get_device_info":        [.system],
        "get_location":           [.system],
        "weather":                [.system],
        "open_url":               [.system],
        "shortcuts":              [.system],

        "health":                 [.health],

        "code_sandbox":           [.code],
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

    /// Determine which tool names to include based on the user's last message.
    /// Always includes `.core` tools. Adds categories whose keywords match the query.
    /// If no specific intent is detected, includes ALL tools (conservative fallback).
    static func filter(toolNames: [String], query: String) -> [String] {
        let lowerQuery = query.lowercased()

        // Determine which categories are relevant
        var activeCategories = Set<Category>([.core])

        for (category, keywords) in categoryKeywords {
            if keywords.contains(where: { lowerQuery.contains($0) }) {
                activeCategories.insert(category)
            }
        }

        // If no specific categories matched (only .core), return ALL tools
        // (conservative: better to have extra tools than miss the right one)
        if activeCategories.count == 1 {
            return toolNames
        }

        // Filter: keep tools that belong to any active category
        let filtered = toolNames.filter { name in
            guard let cats = toolCategories[name] else {
                return true // unknown tools: keep (conservative)
            }
            return !cats.isDisjoint(with: activeCategories)
        }

        // Safety: if filtering removed everything except core, fall back to all
        if filtered.count <= 3 {
            return toolNames
        }

        return filtered
    }
}
