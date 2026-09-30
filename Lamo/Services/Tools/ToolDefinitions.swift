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
    }

    enum Weather {
        static let name = "weather"
        static let description = """
            Current weather + multi-day forecast for a city, or device \
            location when empty (auto-detected). Celsius, km/h.
            """
    }

    enum Calendar {
        static let name = "calendar"
        static let description = """
            Apple Calendar: list, create, or search events. \
            Resolve relative dates via <current_time> first. \
            New events get a 15-minute alarm.
            """
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
    }

    enum WebSearch {
        static let name = "web_search"
        static let description = """
            Web search for current or unknown facts (news, prices). \
            Returns up to 5 results (title, snippet, URL). \
            Answer from snippets when possible; fetch_url only for the 1-2 best pages. \
            Not for weather, calendar, or location.
            """
    }

    enum FetchURL {
        static let name = "fetch_url"
        static let description = """
            Read a page's full text (stripped, cut to budget). \
            Use after web_search or for a user-given URL. \
            Max 1-2 pages per question.
            """
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
