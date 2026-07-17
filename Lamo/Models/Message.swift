import Foundation
import SwiftData

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
    /// @Transient so SwiftData doesn't persist it; no underscore prefix to
    /// avoid collision with SwiftData's generated backing properties.
    @Transient private var benchmarkCache: BenchmarkData?

    var benchmark: BenchmarkData? {
        get {
            if let cached = benchmarkCache { return cached }
            guard let json = benchmarkJSON,
                  let data = json.data(using: .utf8) else { return nil }
            let decoded = try? JSONDecoder().decode(BenchmarkData.self, from: data)
            benchmarkCache = decoded
            return decoded
        }
        set {
            benchmarkCache = newValue
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue) else {
                benchmarkJSON = nil
                return
            }
            benchmarkJSON = String(data: data, encoding: .utf8)
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
        benchmarkJSON: String? = nil
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
    }
}

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}
