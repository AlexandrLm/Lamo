import Foundation

// MARK: - Tool Definitions (single source of truth)

/// Canonical tool names + descriptions shared by LiteRT-LM tools,
/// Foundation Models adapters, and settings UI.
/// Add a new tool here first, then reference these constants everywhere
/// instead of copy-pasting description strings.
enum ToolDefinitions {
    /// All tool names — used for honest "N/M tools" counts in the context menu.
    static let allNames = [
        GetLocation.name, Weather.name, Calendar.name,
        UpdateMemory.name, WebSearch.name, FetchURL.name,
    ]

    enum GetLocation {
        static let name = "get_location"
        static let description = """
            Device location (city + coordinates) via GPS/IP. \
            Only for explicit "where am I". \
            Never before weather.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "\"where am I\" → get_location"
    }

    enum Weather {
        static let name = "weather"
        static let description = """
            Weather + forecast for a city; empty = device location. \
            Celsius, km/h.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "weather/forecast → weather (auto-locates, no get_location)"
    }

    enum Calendar {
        static let name = "calendar"
        static let description = """
            Apple Calendar: list/create/search events. \
            Resolve dates via <current_time>. \
            New events get 15-min alarm.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "events/schedule → calendar"
    }

    enum UpdateMemory {
        static let name = "update_memory"
        static let description = """
            Save user facts (name, city, likes) or when asked. \
            'facts': one sentence each. \
            'forget': exact text, [index], or paraphrase. \
            'summary': 2-3 sentence recap. 'include_existing': read facts. \
            Persistent facts only.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "remember user facts → update_memory"
    }

    enum WebSearch {
        static let name = "web_search"
        static let description = """
            Web search for fresh/unknown facts. \
            Up to 5 results. Prefer snippets; fetch_url only for 1-2 best pages. \
            Not for weather/calendar/location.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "news/prices/fresh facts → web_search (short keywords)"
    }

    enum FetchURL {
        static let name = "fetch_url"
        static let description = """
            Read a page's full text. \
            Use after web_search or for user URLs. \
            Max 1-2 pages.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "read a page → fetch_url (after web_search or user URL)"
    }
}

// MARK: - Reporting helper
/// Builds a stable JSON string for `ToolCallReporter.reportCall`.
/// Replaces hand-rolled string interpolation (which breaks on quotes/newlines).
enum ToolReportHelper {
    static func paramsJSONString(_ dict: [String: Any]) -> String {
        guard !dict.isEmpty else { return "{}" }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

// MARK: - Dynamic prompt section

/// Dynamic per-turn `<tool_availability>` block for the system prompt.
///
/// The base system prompt no longer enumerates tools — it only points at this
/// block. Usage lines are rendered solely for the tools actually registered
/// this turn (settings toggles, network state, topic routing), so disabled
/// tools cost zero prompt tokens and the model never calls them or
/// hallucinates instead of saying "unavailable". Single source of truth —
/// used by both the LiteRT and Foundation Models providers.
enum ToolPromptSection {
    /// Usage lines for the given tool names, in canonical order.
    static func promptLines(for available: [String]) -> [String] {
        let set = Set(available)
        var lines: [String] = []
        if set.contains(ToolDefinitions.Weather.name) { lines.append(ToolDefinitions.Weather.promptLine) }
        if set.contains(ToolDefinitions.GetLocation.name) { lines.append(ToolDefinitions.GetLocation.promptLine) }
        if set.contains(ToolDefinitions.Calendar.name) { lines.append(ToolDefinitions.Calendar.promptLine) }
        if set.contains(ToolDefinitions.WebSearch.name) { lines.append(ToolDefinitions.WebSearch.promptLine) }
        if set.contains(ToolDefinitions.FetchURL.name) { lines.append(ToolDefinitions.FetchURL.promptLine) }
        if set.contains(ToolDefinitions.UpdateMemory.name) { lines.append(ToolDefinitions.UpdateMemory.promptLine) }
        return lines
    }

    /// Builds the `<tool_availability>` block. Emitted every turn: it is the
    /// model's only per-turn tool reference besides the tool schemas.
    static func build(available: [String], unavailable: [String]) -> String {
        var block = "<tool_availability>\nAvailable:\n"
        let lines = promptLines(for: available)
        if lines.isEmpty {
            block += "(none — answer from knowledge; do not call tools)\n"
        } else {
            for line in lines { block += "- \(line)\n" }
        }
        if !unavailable.isEmpty {
            block += "Unavailable: \(unavailable.joined(separator: ", ")). Never call them; say unavailable instead of guessing.\n"
        }
        block += "</tool_availability>"
        return block
    }
}
