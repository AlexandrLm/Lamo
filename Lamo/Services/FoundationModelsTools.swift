import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Native iOS 27 Tool adapters

/// Bridges the app's existing LiteRT-LM tools to the iOS 27 Foundation Models
/// `Tool` protocol, so the on-device `SystemLanguageModel` can call them natively
/// (no manual `<tool_call>` JSON prompt-hacking).
///
/// Each adapter mirrors the wrapped tool's `@ToolParam` fields with a `@Generable`
/// argument struct, serializes them to the exact JSON keys the LiteRT decoder
/// expects, and delegates to `ToolRegistry.executeTool(name:argumentsJSON:)`.
/// UI tool blocks keep working unchanged because the underlying `run()` methods
/// already report call/result via `ToolCallReporter`.
#if canImport(FoundationModels)
@available(iOS 27.0, macOS 27.0, *)
enum FoundationModelsTools {
    /// The FM tools to register on a session, honoring user settings.
    static func enabledTools(networkAvailable: Bool) -> [any Tool] {
        var tools: [any Tool] = [
            FMWeatherTool(),
            FMLocationTool(),
            FMCalendarTool(),
        ]
        if AppDefaults.memoryEnabled.wrappedValue {
            tools.append(FMMemoryTool())
        }
        if networkAvailable {
            if AppDefaults.toolWebSearch.wrappedValue { tools.append(FMWebSearchTool()) }
            if AppDefaults.toolFetchURL.wrappedValue { tools.append(FMFetchURLTool()) }
        }
        return tools
    }
}

// MARK: - Weather

@available(iOS 27.0, macOS 27.0, *)
struct FMWeatherTool: Tool {
    let name = ToolDefinitions.Weather.name
    let description = ToolDefinitions.Weather.description

    @Generable
    struct Arguments {
        @Guide(description: "City name (English spelling works best, e.g. 'Berlin', 'New York'). Leave empty to use the device's current location.")
        var city: String?

        @Guide(description: "Forecast days, 1-7. Use 1-2 for 'today' or 'tomorrow' questions; more only for trip planning.")
        var days: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        var json: [String: Any] = ["city": arguments.city ?? ""]
        if let days = arguments.days { json["days"] = days }
        let result = await ToolRegistry.executeTool(name: ToolDefinitions.Weather.name, argumentsJSON: fmJSONArguments(json))
        return fmFormattedResult(result)
    }
}

// MARK: - Location

@available(iOS 27.0, macOS 27.0, *)
struct FMLocationTool: Tool {
    let name = ToolDefinitions.GetLocation.name
    let description = ToolDefinitions.GetLocation.description

    @Generable
    struct Arguments {
        @Guide(description: "Set true for faster, less accurate IP-based location (also works when GPS permission is denied).")
        var ipOnly: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        var json: [String: Any] = [:]
        if let ipOnly = arguments.ipOnly { json["ipOnly"] = ipOnly }
        let result = await ToolRegistry.executeTool(name: ToolDefinitions.GetLocation.name, argumentsJSON: fmJSONArguments(json))
        return fmFormattedResult(result)
    }
}

// MARK: - Calendar

@available(iOS 27.0, macOS 27.0, *)
struct FMCalendarTool: Tool {
    let name = ToolDefinitions.Calendar.name
    let description = ToolDefinitions.Calendar.description

    @Generable
    struct Arguments {
        @Guide(description: "'list' shows events in a date range, 'create' adds a new event (requires a title), 'search' finds events by keyword in title/notes/location.")
        var mode: String?

        @Guide(description: "Date in YYYY-MM-DD format. For list: range start (default today). For create: the event day (default today).")
        var startDate: String?

        @Guide(description: "Date in YYYY-MM-DD format. For list: range end (default 7 days after start).")
        var endDate: String?

        @Guide(description: "Event title. Required for create.")
        var title: String?

        @Guide(description: "Event notes, for create.")
        var notes: String?

        @Guide(description: "Event location, for create.")
        var location: String?

        @Guide(description: "Start time HH:MM (24-hour), for create. When omitted, the event is all-day.")
        var startTime: String?

        @Guide(description: "End time HH:MM (24-hour), for create. Default: one hour after start.")
        var endTime: String?

        @Guide(description: "Keyword to find, for search.")
        var query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        var json: [String: Any] = [:]
        if let v = arguments.mode { json["mode"] = v }
        if let v = arguments.startDate { json["startDate"] = v }
        if let v = arguments.endDate { json["endDate"] = v }
        if let v = arguments.title { json["title"] = v }
        if let v = arguments.notes { json["notes"] = v }
        if let v = arguments.location { json["location"] = v }
        if let v = arguments.startTime { json["startTime"] = v }
        if let v = arguments.endTime { json["endTime"] = v }
        if let v = arguments.query { json["query"] = v }
        let result = await ToolRegistry.executeTool(name: ToolDefinitions.Calendar.name, argumentsJSON: fmJSONArguments(json))
        return fmFormattedResult(result)
    }
}

// MARK: - Memory

@available(iOS 27.0, macOS 27.0, *)
struct FMMemoryTool: Tool {
    let name = ToolDefinitions.UpdateMemory.name
    let description = ToolDefinitions.UpdateMemory.description

    @Generable
    struct Arguments {
        @Guide(description: "New facts about the user to remember. Each fact is one short sentence. Old contradictory facts are auto-replaced.")
        var facts: [String]?

        @Guide(description: "Exact full text of facts to forget (not substring). Use include_existing=true first to see current facts and copy exact text.")
        var forget: [String]?

        @Guide(description: "Brief summary of the conversation so far (2-3 sentences). Use when conversation is long.")
        var summary: String?

        @Guide(description: "Set to true to read back all currently stored facts. Always do this before forgetting or updating.")
        var includeExisting: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        var json: [String: Any] = [:]
        if let v = arguments.facts { json["facts"] = v }
        if let v = arguments.forget { json["forget"] = v }
        if let v = arguments.summary { json["summary"] = v }
        if let v = arguments.includeExisting { json["includeExisting"] = v }
        let result = await ToolRegistry.executeTool(name: ToolDefinitions.UpdateMemory.name, argumentsJSON: fmJSONArguments(json))
        return fmFormattedResult(result)
    }
}

// MARK: - Web search

@available(iOS 27.0, macOS 27.0, *)
struct FMWebSearchTool: Tool {
    let name = ToolDefinitions.WebSearch.name
    let description = ToolDefinitions.WebSearch.description

    @Generable
    struct Arguments {
        @Guide(description: "Short keyword query (2-6 words works best), NOT a full sentence. Write it in the user's language.")
        var query: String

        @Guide(description: "Number of results, 1-5. The default 5 is enough for most questions — prefer 3 to save context.")
        var maxResults: Int?

        @Guide(description: "Freshness filter: 'day', 'week', 'month', or 'year'. Set only when the user asks about recent events.")
        var timeRange: String?
    }

    func call(arguments: Arguments) async throws -> String {
        var json: [String: Any] = ["query": arguments.query]
        if let v = arguments.maxResults { json["maxResults"] = v }
        if let v = arguments.timeRange { json["timeRange"] = v }
        let result = await ToolRegistry.executeTool(name: ToolDefinitions.WebSearch.name, argumentsJSON: fmJSONArguments(json))
        return fmFormattedResult(result)
    }
}

// MARK: - Fetch URL

@available(iOS 27.0, macOS 27.0, *)
struct FMFetchURLTool: Tool {
    let name = ToolDefinitions.FetchURL.name
    let description = ToolDefinitions.FetchURL.description

    @Generable
    struct Arguments {
        @Guide(description: "Full URL starting with http:// or https:// — copy it exactly from a search result or the user's message.")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        let result = await ToolRegistry.executeTool(name: ToolDefinitions.FetchURL.name, argumentsJSON: fmJSONArguments(["url": arguments.url]))
        return fmFormattedResult(result)
    }
}

// MARK: - Helpers

/// Serialize tool arguments to the JSON string the LiteRT decoder expects.
@available(iOS 27.0, macOS 27.0, *)
nonisolated private func fmJSONArguments(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let str = String(data: data, encoding: .utf8) else { return "{}" }
    return str
}

/// Format a tool result dictionary for the model, truncating at a character boundary.
@available(iOS 27.0, macOS 27.0, *)
nonisolated private func fmFormattedResult(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
          let str = String(data: data, encoding: .utf8) else {
        return "\(dict)"
    }
    if str.count > 4000 {
        return String(str.prefix(4000)) + "\n…[truncated]"
    }
    return str
}
#endif
