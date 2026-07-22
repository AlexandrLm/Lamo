import Foundation
import SwiftData

/// A single tool invocation within a message — call and optional result.
struct ToolCallRecord: Codable, Identifiable {
    var id: UUID
    var name: String
    var params: String
    var result: String?
    var timestamp: Date

    init(id: UUID = UUID(), name: String, params: String, result: String? = nil, timestamp: Date = .now) {
        self.id = id
        self.name = name
        self.params = params
        self.result = result
        self.timestamp = timestamp
    }
}

@Model
final class Message {
    var id: UUID
    var content: String
    var thinkingContent: String
    var roleRaw: String
    var timestamp: Date
    var isStreaming: Bool
    /// Paths to attached images (stored in app's tmp directory).
    var imagePaths: [String] = []
    /// Paths to attached non-image files (PDF, DOCX, etc.).
    var attachedFilePaths: [String] = []
    /// Names of attached non-image files (for display).
    var attachedFileNames: [String] = []
    /// Sizes of attached files (formatted strings for display).
    var attachedFileSizes: [String] = []
    /// Extracted text content from attached files (sent to model separately, not shown in UI).
    var fileContent: String = ""

    @Relationship(inverse: \Conversation.messages)
    var conversation: Conversation?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var hasImages: Bool { !imagePaths.isEmpty }
    var hasAttachedFiles: Bool { !attachedFilePaths.isEmpty }

    /// JSON-encoded BenchmarkData for this response.
    var benchmarkJSON: String?

    /// Cached decoded BenchmarkData — avoids JSON decode on every access.
    @Transient private var benchmarkCache: BenchmarkData?

    var benchmark: BenchmarkData? {
        get {
            if let cached = benchmarkCache { return cached }
            guard let json = benchmarkJSON else { return nil }
            let decoded = BenchmarkData.decode(from: json)
            benchmarkCache = decoded
            return decoded
        }
        set {
            benchmarkCache = newValue
            if let newValue {
                benchmarkJSON = newValue.encode()
            } else {
                benchmarkJSON = nil
            }
        }
    }

    /// JSON-encoded array of ToolCallRecord for this response.
    var toolCallsJSON: String?

    /// Decoded tool calls — cached for performance.
    @Transient private var toolCallsCache: [ToolCallRecord]?

    var toolCalls: [ToolCallRecord] {
        get {
            if let cached = toolCallsCache { return cached }
            guard let json = toolCallsJSON,
                  let data = json.data(using: .utf8) else { return [] }
            let decoded = (try? JSONDecoder().decode([ToolCallRecord].self, from: data)) ?? []
            toolCallsCache = decoded
            return decoded
        }
        set {
            toolCallsCache = newValue
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                toolCallsJSON = nil
                return
            }
            toolCallsJSON = json
        }
    }

    init(
        id: UUID = UUID(),
        content: String,
        thinkingContent: String = "",
        role: MessageRole,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        imagePaths: [String] = [],
        attachedFilePaths: [String] = [],
        attachedFileNames: [String] = [],
        attachedFileSizes: [String] = [],
        fileContent: String = "",
        conversation: Conversation? = nil,
        benchmarkJSON: String? = nil,
        toolCallsJSON: String? = nil
    ) {
        self.id = id
        self.content = content
        self.thinkingContent = thinkingContent
        self.roleRaw = role.rawValue
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.imagePaths = imagePaths
        self.attachedFilePaths = attachedFilePaths
        self.attachedFileNames = attachedFileNames
        self.attachedFileSizes = attachedFileSizes
        self.fileContent = fileContent
        self.conversation = conversation
        self.benchmarkJSON = benchmarkJSON
        self.toolCallsJSON = toolCallsJSON
    }
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}
