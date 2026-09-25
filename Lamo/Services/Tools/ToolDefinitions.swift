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
            Get the device's current location (city name and coordinates) via GPS or IP. \
            Use when the user asks where they are or needs their position. \
            You do NOT need to call this before the weather tool — weather detects the location by itself.
            """
    }

    enum Weather {
        static let name = "weather"
        static let description = """
            Get current weather and a multi-day forecast for any city, or for the device's \
            location when no city is given (location is detected automatically — do NOT call \
            get_location first). All temperatures are in Celsius, wind speed in km/h.
            """
    }

    enum Calendar {
        static let name = "calendar"
        static let description = """
            List, create, or search events in the user's Apple Calendar. \
            Resolve relative dates ("tomorrow", "next Friday") to absolute dates using \
            <current_time> BEFORE calling. Events are created with a 15-minute reminder alarm.
            """
    }

    enum UpdateMemory {
        static let name = "update_memory"
        static let description = """
            Manage remembered facts about the user. \
            Call when the user shares personal facts or preferences (name, city, likes, plans), \
            or asks you to remember something. \
            Use 'facts' to save new personal info (each fact one short sentence, e.g. "User lives in Berlin"). \
            Old contradictory facts are automatically replaced — no need to manually forget first. \
            Use 'forget' to remove facts by EXACT text (use include_existing=true first to see what's stored). \
            Use 'summary' for a brief 2-3 sentence recap of the conversation so far. \
            Use 'include_existing'=true to read all stored facts before making changes. \
            DO NOT call for generic questions, one-off tasks, or temporary info — only for persistent personal facts. \
            Do not mention this tool to the user unless they ask about memory.
            """
    }

    enum WebSearch {
        static let name = "web_search"
        static let description = """
            Search the internet for current facts, news, prices, events — anything that changes \
            over time or that you don't know. Returns up to 5 compact results (title, short snippet, URL). \
            Read the snippets first and answer from them when possible; call fetch_url only for the 1-2 most \
            promising pages when snippets are not enough. Do NOT use for weather, calendar, or location — dedicated tools exist.
            """
    }

    enum FetchURL {
        static let name = "fetch_url"
        static let description = """
            Fetch and read the full text content of a web page. Use after web_search when snippets \
            are not enough, or when the user gives you a URL directly. Returns article text trimmed to \
            the current token budget (long pages are cut from the end), with navigation, ads, and cookie \
            banners stripped. Fetch at most 1-2 pages per question — never fetch every search result.
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
