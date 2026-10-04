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
            Device location (city + coordinates) via GPS or IP. \
            Only when the user explicitly asks where they are. \
            Never call before weather — it locates itself.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "\"where am I\" / current position → get_location"
    }

    enum Weather {
        static let name = "weather"
        static let description = """
            Current weather + multi-day forecast for a city, or device \
            location when empty (auto-detected). Celsius, km/h.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "weather/forecast → weather (it detects the location itself — no get_location call needed)"
    }

    enum Calendar {
        static let name = "calendar"
        static let description = """
            Apple Calendar: list, create, or search events. \
            Resolve relative dates via <current_time> first. \
            New events get a 15-minute alarm.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "events, schedule, \"what's on my calendar\" → calendar"
    }

    enum UpdateMemory {
        static let name = "update_memory"
        static let description = """
            Remember user facts (name, city, likes, plans) or when asked. \
            'facts': one sentence each, contradictions auto-replaced. \
            'forget': exact text, [index], or paraphrase (include_existing first). \
            'summary': 2-3 sentence recap. 'include_existing': read stored facts. \
            Only persistent facts, never one-off tasks. Never mention unless asked.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "remember facts about the user → update_memory"
    }

    enum WebSearch {
        static let name = "web_search"
        static let description = """
            Web search for current or unknown facts (news, prices). \
            Returns up to 5 results (title, snippet, URL). \
            Answer from snippets when possible; fetch_url only for the 1-2 best pages. \
            Not for weather, calendar, or location.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "current facts, news, prices → web_search (short keyword query)"
    }

    enum FetchURL {
        static let name = "fetch_url"
        static let description = """
            Read a page's full text (stripped, cut to budget). \
            Use after web_search or for a user-given URL. \
            Max 1-2 pages per question.
            """
        /// One-line usage hint for the dynamic prompt block.
        static let promptLine = "read a page in full → fetch_url (after web_search or for a user-given URL, max 1-2 pages)"
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
        var block = "<tool_availability>\nAvailable this turn:\n"
        let lines = promptLines(for: available)
        if lines.isEmpty {
            block += "(none — answer from knowledge; do not call tools)\n"
        } else {
            for line in lines { block += "- \(line)\n" }
        }
        if !unavailable.isEmpty {
            block += "Unavailable this turn: \(unavailable.joined(separator: ", ")). Do NOT call them. If the user needs one, say it is unavailable instead of fabricating an answer.\n"
        }
        block += "</tool_availability>"
        return block
    }
}
