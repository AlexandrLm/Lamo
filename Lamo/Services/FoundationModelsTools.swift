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
    static func enabledTools(networkAvailable: Bool, userText: String = "") -> [any Tool] {
        let route = ToolRouter.route(for: userText)
        var tools: [any Tool] = []
        if AppDefaults.toolWeather.wrappedValue && route.weather { tools.append(FMWeatherTool()) }
        if AppDefaults.toolGetLocation.wrappedValue && route.location { tools.append(FMLocationTool()) }
        if AppDefaults.toolCalendar.wrappedValue && route.calendar { tools.append(FMCalendarTool()) }
        if AppDefaults.memoryEnabled.wrappedValue {
            tools.append(FMMemoryTool())
        }
        if networkAvailable {
            if AppDefaults.toolWebSearch.wrappedValue && route.webSearch { tools.append(FMWebSearchTool()) }
            if AppDefaults.toolFetchURL.wrappedValue && route.fetchURL { tools.append(FMFetchURLTool()) }
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
        @Guide(description: "City (English best). Empty = device location.")
        var city: String?

        @Guide(description: "Days 1-7 (default 3; 1-2 for today).")
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
        @Guide(description: "true = fast IP location, no GPS needed.")
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
        @Guide(description: "'list' (date range), 'create' (needs title), 'search' (keyword).")
        var mode: String?

        @Guide(description: "Start YYYY-MM-DD (default today).")
        var startDate: String?

        @Guide(description: "End YYYY-MM-DD (default +7 days).")
        var endDate: String?

        @Guide(description: "Title (required for create).")
        var title: String?

        @Guide(description: "Notes.")
        var notes: String?

        @Guide(description: "Location.")
        var location: String?

        @Guide(description: "Start HH:MM (all-day if omitted).")
        var startTime: String?

        @Guide(description: "End HH:MM (default +1h).")
        var endTime: String?

        @Guide(description: "Search keyword.")
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

        @Guide(description: "Forget: exact text, [index], or paraphrase (include_existing first).")
        var forget: [String]?

        @Guide(description: "2-3 sentence recap for long chats.")
        var summary: String?

        @Guide(description: "true = read stored facts first.")
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
        @Guide(description: "Keywords, 2-6 words, user language.")
        var query: String

        @Guide(description: "1-5 results (default 5, prefer 3).")
        var maxResults: Int?

        @Guide(description: "day/week/month/year, only for recent events.")
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
        @Guide(description: "Full secure URL starting with https:// — copy it exactly from a search result or the user's message.")
        var url: String
    }

    func call(arguments: Arguments) async throws -> String {
        let result = await ToolRegistry.executeTool(name: ToolDefinitions.FetchURL.name, argumentsJSON: fmJSONArguments(["url": arguments.url]))
        return fmFormattedResult(result)
    }
}

// MARK: - Helpers

@available(iOS 27.0, macOS 27.0, *)
nonisolated private func fmJSONArguments(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict),
          let str = String(data: data, encoding: .utf8) else { return "{}" }
    return str
}

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
