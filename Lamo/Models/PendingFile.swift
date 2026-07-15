import Foundation
import UniformTypeIdentifiers

/// Represents a file attached to the current input, waiting to be sent.
struct PendingFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let type: UTType

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.type = UTType(filenameExtension: url.pathExtension) ?? .data
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var iconName: String {
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .sourceCode) || type.conforms(to: .swiftSource) || type.conforms(to: .cSource) || type.conforms(to: .javaScript) || type.conforms(to: .pythonScript) { return "chevron.left.forwardslash.chevron.right" }
        if type.conforms(to: .plainText) || type.conforms(to: .json) || type.conforms(to: .xml) { return "doc.text" }
        if type.conforms(to: .spreadsheet) || url.pathExtension == "csv" { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        return "doc"
    }

    var isImage: Bool { type.conforms(to: .image) }

    var isAudio: Bool { type.conforms(to: .audio) || type.conforms(to: .movie) }

    static func == (lhs: PendingFile, rhs: PendingFile) -> Bool {
        lhs.id == rhs.id
    }
}
