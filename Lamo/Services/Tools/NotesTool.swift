import Foundation
import LiteRTLM

// MARK: - Notes Tool

struct NotesTool: Tool {
    static let name = "notes"
    static let description = "Manage personal notes."

    @ToolParam(description: "Operation: list, search, read, create, or delete.")
    var mode: String

    @ToolParam(description: "Note title. Required for read, create, and delete.")
    var title: String?

    @ToolParam(description: "Note content. Used in create mode.")
    var content: String?

    @ToolParam(description: "Search query. Case-insensitive match against titles and content.")
    var query: String?

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(name: Self.name, params: paramsJSON())

        let result: [String: Any]
        switch mode.lowercased() {
        case "list":
            result = listNotes()
        case "search":
            result = searchNotes()
        case "read":
            result = await readNote()
        case "create":
            result = createNote()
        case "delete":
            result = deleteNote()
        default:
            result = ["error": "Unknown mode '\(mode)'. Valid modes: list, search, read, create, delete."]
        }

        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }

    // MARK: - Storage

    private var notesURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("lamo_notes.json")
    }

    private func loadNotes() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: notesURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    private func saveNotes(_ notes: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: notes, options: .prettyPrinted) else {
            return
        }
        try? data.write(to: notesURL, options: .atomic)
    }

    private func nowISO() -> String {
        let fmtr = ISO8601DateFormatter()
        fmtr.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmtr.string(from: Date())
    }

    // MARK: - Modes

    private func listNotes() -> [String: Any] {
        let notes = loadNotes()
        let summaries: [[String: Any]] = notes.compactMap { note in
            guard let title = note["title"] as? String else { return nil }
            return ["title": title, "created_at": note["created_at"] ?? ""]
        }
        return ["mode": "list", "count": summaries.count, "notes": summaries]
    }

    private func searchNotes() -> [String: Any] {
        guard let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty else {
            return ["error": "Query is required for search mode."]
        }
        let notes = loadNotes()
        let lowerQuery = query.lowercased()
        let matches: [[String: Any]] = notes.compactMap { note in
            guard let title = note["title"] as? String else { return nil }
            let noteContent = note["content"] as? String ?? ""
            if title.lowercased().contains(lowerQuery) || noteContent.lowercased().contains(lowerQuery) {
                return ["title": title, "created_at": note["created_at"] ?? ""]
            }
            return nil
        }
        return ["mode": "search", "query": query, "count": matches.count, "notes": matches]
    }

    private func readNote() async -> [String: Any] {
        guard let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            return ["error": "Title is required for read mode."]
        }
        var notes = loadNotes()
        guard let index = notes.firstIndex(where: { ($0["title"] as? String) == title }) else {
            return ["error": "Note '\(title)' not found."]
        }
        var note = notes[index]
        if let rawContent = note["content"] as? String {
            let limit = await AgenticLoopBudget.shared.consumeIteration()
            let truncated = await TokenTruncator.truncate(rawContent, maxTokens: limit)
            note["content"] = truncated
        }
        return ["mode": "read", "note": note]
    }

    private func createNote() -> [String: Any] {
        guard let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            return ["error": "Title is required for create mode."]
        }
        let body = content ?? ""
        let timestamp = nowISO()

        var notes = loadNotes()
        if let index = notes.firstIndex(where: { ($0["title"] as? String) == title }) {
            // Overwrite existing
            notes[index]["content"] = body
            notes[index]["updated_at"] = timestamp
            saveNotes(notes)
            return ["mode": "create", "action": "updated", "title": title]
        } else {
            let note: [String: Any] = [
                "title": title,
                "content": body,
                "created_at": timestamp,
                "updated_at": timestamp,
            ]
            notes.append(note)
            saveNotes(notes)
            return ["mode": "create", "action": "created", "title": title]
        }
    }

    private func deleteNote() -> [String: Any] {
        guard let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
            return ["error": "Title is required for delete mode."]
        }
        var notes = loadNotes()
        guard let index = notes.firstIndex(where: { ($0["title"] as? String) == title }) else {
            return ["error": "Note '\(title)' not found."]
        }
        notes.remove(at: index)
        saveNotes(notes)
        return ["mode": "delete", "title": title, "deleted": true]
    }

    // MARK: - Helpers

    private func paramsJSON() -> String {
        var parts: [String] = ["\"mode\": \"\(mode)\""]
        if let t = title { parts.append("\"title\": \"\(t)\"") }
        if let c = content { parts.append("\"content\": \"\(c)\"") }
        if let q = query { parts.append("\"query\": \"\(q)\"") }
        return "{\(parts.joined(separator: ", "))}"
    }
}
