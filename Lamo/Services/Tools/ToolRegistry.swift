import Foundation
@preconcurrency import LiteRTLM
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Tool Registry for Foundation Models

/// Bridges existing LiteRT-LM tools to Foundation Models compatible format.
/// Single switch on tool name — adding a tool means adding one case here.
enum ToolRegistry {

    /// Execute a tool by name with JSON arguments string.
    /// Returns the tool's result as a dictionary or error description.
    static func executeTool(name: String, argumentsJSON: String) async -> [String: Any] {
        guard let argsData = argumentsJSON.data(using: .utf8) else {
            return ["error": String(localized: "Failed to encode arguments"), "hint": "Ensure arguments are valid JSON."]
        }
        do {
            let decoder = JSONDecoder()
            let result: Any
            switch name {
            case GetLocationTool.name:
                result = try await decoder.decode(GetLocationTool.self, from: argsData).run()
            case WeatherTool.name:
                result = try await decoder.decode(WeatherTool.self, from: argsData).run()
            case CalendarTool.name:
                result = try await decoder.decode(CalendarTool.self, from: argsData).run()
            case UpdateMemoryTool.name:
                result = try await decoder.decode(UpdateMemoryTool.self, from: argsData).run()
            case WebSearchTool.name:
                result = try await decoder.decode(WebSearchTool.self, from: argsData).run()
            case FetchUrlTool.name:
                result = try await decoder.decode(FetchUrlTool.self, from: argsData).run()
            default:
                return [
                    "error": String(localized: "Unknown tool: '\(name)'"),
                    "hint": "Check the tool name and available tools list.",
                ]
            }
            return normalizeResult(result)
        } catch {
            return [
                "error": String(localized: "Tool execution failed: \(error.localizedDescription)"),
                "hint": "Check the arguments format and retry once with corrected values.",
            ]
        }
    }

    // MARK: - Private

    private static func normalizeResult(_ result: Any) -> [String: Any] {
        if let dict = result as? [String: Any] {
            return dict
        } else if let string = result as? String {
            return ["result": string]
        } else {
            return ["result": "\(result)"]
        }
    }
}
