import Foundation
import UniformTypeIdentifiers

/// Represents a file attached to the current input, waiting to be sent.
nonisolated struct PendingFile: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let type: UTType

    /// Shared formatter — ByteCountFormatter init is expensive, never alloc per row.
    static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f
    }()

    /// Cache for iconName lookups keyed by type identifier — UTType.conforms(to:)
    /// walks the type tree, so memoize per identifier.
    private static var iconNameCache: [String: String] = [:]
    private static let iconNameCacheLock = NSLock()

    /// Designated init with ready-made size — do file-system IO outside (list rows,
    /// drop delegates) and pass the result in, keeping init cheap and Sendable-friendly.
    init(id: UUID = UUID(), url: URL, name: String? = nil, size: Int64, type: UTType? = nil) {
        self.id = id
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.type = type ?? UTType(filenameExtension: url.pathExtension) ?? .data
    }

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.type = UTType(filenameExtension: url.pathExtension) ?? .data
    }

    var formattedSize: String {
        Self.sizeFormatter.string(fromByteCount: size)
    }

    var iconName: String {
        let key = type.identifier
        Self.iconNameCacheLock.lock()
        if let cached = Self.iconNameCache[key] {
            Self.iconNameCacheLock.unlock()
            return cached
        }
        Self.iconNameCacheLock.unlock()
        let resolved = Self.resolveIconName(for: type, pathExtension: url.pathExtension)
        Self.iconNameCacheLock.lock()
        Self.iconNameCache[key] = resolved
        Self.iconNameCacheLock.unlock()
        return resolved
    }

    private static func resolveIconName(for type: UTType, pathExtension: String) -> String {
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        let codeTypes: [UTType] = [.sourceCode, .swiftSource, .cSource, .javaScript, .pythonScript]
        if codeTypes.contains(where: { type.conforms(to: $0) }) {
            return "chevron.left.forwardslash.chevron.right"
        }
        if type.conforms(to: .plainText) || type.conforms(to: .json) || type.conforms(to: .xml) { return "doc.text" }
        if type.conforms(to: .spreadsheet) || pathExtension == "csv" { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        return "doc"
    }

    var isImage: Bool { type.conforms(to: .image) }

    var isAudio: Bool { type.conforms(to: .audio) || type.conforms(to: .movie) }

    static func == (lhs: PendingFile, rhs: PendingFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
