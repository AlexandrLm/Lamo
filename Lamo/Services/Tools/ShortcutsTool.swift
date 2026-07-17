import Foundation
import LiteRTLM
import UIKit

// MARK: - Run Shortcut

struct ShortcutsTool: Tool {
    static let name = "shortcuts"
    static let description = "Run a Siri Shortcut by name."

    @ToolParam(description: "Exact name of the shortcut to run.")
    var name: String

    @ToolParam(description: "Optional text input to pass to the shortcut.")
    var input: String?

    func run() async throws -> Any {
        var paramsDesc = "{\"name\": \"\(name)\""
        if let input { paramsDesc += ", \"input\": \"\(input)\"" }
        paramsDesc += "}"
        await ToolCallReporter.shared.reportCall(name: Self.name, params: paramsDesc)

        // Check whether Shortcuts app can be reached
        guard let testURL = URL(string: "shortcuts://") else {
            let result: [String: Any] = ["success": false, "shortcut": name, "error": "Could not construct Shortcuts URL scheme."]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        }

        let canOpen = await UIApplication.shared.canOpenURL(testURL)
        guard canOpen else {
            let result: [String: Any] = [
                "success": false,
                "shortcut": name,
                "error": "Shortcuts app is not installed on this device."
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        }

        // Build the x-callback-url for running the shortcut
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let runURL = URL(string: "shortcuts://x-callback-url/run-shortcut?name=\(encodedName)\(inputQueryFragment)") else {
            let result: [String: Any] = ["success": false, "shortcut": name, "error": "Could not encode shortcut name for URL."]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        }

        await MainActor.run { UIApplication.shared.open(runURL) }

        let result: [String: Any] = [
            "success": true,
            "shortcut": name,
            "note": "Shortcut '\(name)' launched. Output appears in the Shortcuts app."
        ]
        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }

    // MARK: - Private

    private var inputQueryFragment: String {
        guard let input, !input.isEmpty,
              let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ""
        }
        return "&input=\(encoded)"
    }
}
