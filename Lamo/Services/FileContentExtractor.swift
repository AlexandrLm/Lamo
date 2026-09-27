import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import os

/// Extracts readable text from various file formats for LLM consumption.
nonisolated enum FileContentExtractor {
    private static let logger = Logger(subsystem: LamoLogger.subsystem, category: "FileExtractor")

    /// Max characters to extract per file (to stay within token budget).
    static let maxCharsPerFile = 15_000
    /// Refuse to load files larger than this into memory.
    static let maxFileBytes = 5 * 1024 * 1024

    /// Extract text content from a file URL.
    static func extract(from url: URL) async throws -> String {
        try checkFileSize(url)
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        let name = url.lastPathComponent

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let raw: String

        if type.conforms(to: .pdf) {
            raw = try extractPDFText(from: url)
        } else if url.pathExtension == "docx" {
            raw = try extractDOCX(from: url)
        } else if url.pathExtension == "xlsx" || url.pathExtension == "csv" {
            raw = try extractSpreadsheet(from: url)
        } else if url.pathExtension == "pptx" {
            raw = try extractPPTX(from: url)
        } else {
            // Every remaining type is read as text: known text extensions are
            // checked explicitly, unknown ones get one decoding attempt and a
            // clear error if that fails.
            raw = try readTextFile(from: url)
        }

        let truncated = raw.count > maxCharsPerFile
            ? String(raw.prefix(maxCharsPerFile)) + "\n\n[\(String(localized: "File truncated — showing first \(maxCharsPerFile) of \(raw.count) characters"))]"
            : raw

        return """
        <file name="\(name)">
        \(truncated)
        </file>
        """
    }

    /// For scanned/image PDFs — render pages as images for multimodal models.
    /// Returns rendered page images (max 20 pages, 2x scale).
    static func extractPDFImages(from url: URL) -> [UIImage] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var images: [UIImage] = []
        let maxPages = min(doc.pageCount, 20)

        for i in 0..<maxPages {
            let image: UIImage? = autoreleasepool {
                guard let page = doc.page(at: i) else { return nil as UIImage? }
                let pageRect = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2.0
                let width = pageRect.width * scale
                let height = pageRect.height * scale
                guard width > 0, height > 0, width < 8000, height < 8000 else { return nil as UIImage? }

                let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
                let rendered = renderer.image { ctx in
                    UIColor.white.set()
                    ctx.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
                    ctx.cgContext.translateBy(x: 0, y: height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                return rendered as UIImage?
            }
            if let image { images.append(image) }
        }
        return images
    }

    /// Check if a PDF has a text layer (true) or is scanned/image-only (false).
    static func pdfHasTextLayer(_ url: URL) -> Bool {
        guard let doc = PDFDocument(url: url) else { return false }
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i),
               let text = page.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }
        return false
    }

    // MARK: - Plain Text

    private static func checkFileSize(_ url: URL) throws {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxFileBytes {
            throw FileExtractorError.fileTooLarge(url.lastPathComponent)
        }
    }

    private static func readTextFile(from url: URL) throws -> String {
        try checkFileSize(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .windowsCP1251)
        else {
            throw FileExtractorError.unsupportedFormat(url.lastPathComponent)
        }
        return text
    }

    // MARK: - PDF Text

    private static func extractPDFText(from url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw FileExtractorError.unsupportedFormat(url.lastPathComponent)
        }
        // Single pass: accumulate directly, one autoreleasepool per page so
        // large PDFs don't balloon peak memory. Stops early once the char
        // budget is reached.
        var result = ""
        result.reserveCapacity(min(maxCharsPerFile, 16384))
        for i in 0..<doc.pageCount {
            let chunk: String? = autoreleasepool {
                guard let page = doc.page(at: i),
                      let text = page.string,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil as String? }
                return String(localized: "--- Page \(i + 1) ---") + "\n\(text)"
            }
            if let chunk {
                if !result.isEmpty { result += "\n\n" }
                result += chunk
                if result.count >= maxCharsPerFile { break }
            }
        }
        guard !result.isEmpty else {
            return "[\(String(localized: "PDF has no text layer — content sent as images"))]"
        }
        return result
    }

    // MARK: - DOCX

    private static func extractDOCX(from url: URL) throws -> String {
        try checkFileSize(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard var archive = try? ZipArchive(data: data) else {
            throw FileExtractorError.unsupportedFormat("DOCX")
        }
        guard let xmlData = archive.readEntry("word/document.xml") else {
            throw FileExtractorError.unsupportedFormat("DOCX")
        }
        return extractTextFromOOXML(xmlData)
    }

    // MARK: - XLSX / CSV

    private static func extractSpreadsheet(from url: URL) throws -> String {
        if url.pathExtension == "csv" {
            return try readTextFile(from: url)
        }
        try checkFileSize(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard var archive = try? ZipArchive(data: data) else {
            throw FileExtractorError.unsupportedFormat("XLSX")
        }
        var sharedStrings: [String] = []
        if let ssData = archive.readEntry("xl/sharedStrings.xml") {
            sharedStrings = parseSharedStrings(ssData)
        }
        guard let sheetData = archive.readEntry("xl/worksheets/sheet1.xml") else {
            throw FileExtractorError.unsupportedFormat("XLSX")
        }
        return parseXLSXSheet(sheetData, sharedStrings: sharedStrings)
    }

    // MARK: - PPTX

    private static func extractPPTX(from url: URL) throws -> String {
        try checkFileSize(url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard var archive = try? ZipArchive(data: data) else {
            throw FileExtractorError.unsupportedFormat("PPTX")
        }
        var slides: [String] = []
        for i in 1...100 {
            let path = "ppt/slides/slide\(i).xml"
            guard let slideData = archive.readEntry(path) else { break }
            let text = extractTextFromOOXML(slideData)
            if !text.isEmpty {
                slides.append(String(localized: "--- Slide \(i) ---") + "\n\(text)")
            }
        }
        guard !slides.isEmpty else { return "[\(String(localized: "PPTX contains no text"))]" }
        return slides.joined(separator: "\n\n")
    }

    // MARK: - XML Helpers

    private static let xmlTextPattern: NSRegularExpression = {
        (try? NSRegularExpression(pattern: ">([^<]+)<", options: [])) ?? NSRegularExpression()
    }()

    private static func extractTextFromOOXML(_ data: Data) -> String {
        guard let xml = String(data: data, encoding: .utf8) else { return "" }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = xmlTextPattern.matches(in: xml, range: range)
        let texts = matches.compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: xml) else { return nil }
            let text = String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return texts.joined(separator: " ")
    }

    private static let sharedStringItemPattern: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<si[^>]*>(.*?)</si>", options: [.dotMatchesLineSeparators])) ?? NSRegularExpression()
    }()

    private static let sharedStringTextPattern: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<t[^>]*>(.*?)</t>", options: [.dotMatchesLineSeparators])) ?? NSRegularExpression()
    }()

    /// One `<si>` element is ONE logical string and may contain several `<t>`
    /// runs (formatting splits). Capturing only the first run silently truncates
    /// such values, so concatenate every run inside the element.
    private static func parseSharedStrings(_ data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        return sharedStringItemPattern.matches(in: xml, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: xml) else { return nil }
            let item = String(xml[r])
            let itemRange = NSRange(item.startIndex..., in: item)
            let runs = sharedStringTextPattern.matches(in: item, range: itemRange).compactMap { run -> String? in
                guard run.numberOfRanges > 1, let rr = Range(run.range(at: 1), in: item) else { return nil }
                return String(item[rr])
            }
            let joined = unescapeXML(runs.joined())
            return joined.isEmpty ? nil : joined
        }
    }

    private static let xmlEntityPattern: NSRegularExpression = {
        (try? NSRegularExpression(
            pattern: "&(#x[0-9A-Fa-f]+|#[0-9]+|amp|lt|gt|quot|apos);",
            options: []
        )) ?? NSRegularExpression()
    }()

    /// Decode XML escapes exactly once. Chained `replacingOccurrences` calls
    /// would turn `&amp;lt;` into `<` instead of the literal `&lt;`.
    private static func unescapeXML(_ text: String) -> String {
        let matches = xmlEntityPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let full = Range(match.range(at: 0), in: result),
                  let entityRange = Range(match.range(at: 1), in: result) else { continue }
            let entity = String(result[entityRange])
            let replacement: String
            switch entity {
            case "amp": replacement = "&"
            case "lt": replacement = "<"
            case "gt": replacement = ">"
            case "quot": replacement = "\""
            case "apos": replacement = "'"
            default:
                let value: UInt32?
                if entity.hasPrefix("#x") {
                    value = UInt32(entity.dropFirst(2), radix: 16)
                } else if entity.hasPrefix("#") {
                    value = UInt32(entity.dropFirst(), radix: 10)
                } else {
                    value = nil
                }
                guard let value, let scalar = UnicodeScalar(value) else { continue }
                replacement = String(Character(scalar))
            }
            result.replaceSubrange(full, with: replacement)
        }
        return result
    }

    // MARK: - XLSX Helpers

    private static let xlsxRowPattern: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<row[^>]*>(.*?)</row>", options: [.dotMatchesLineSeparators])) ?? NSRegularExpression()
    }()
    private static let xlsxCellPattern: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<c([^>]*)>(.*?)</c>", options: [.dotMatchesLineSeparators])) ?? NSRegularExpression()
    }()
    private static let xlsxValuePattern: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<v[^>]*>(.*?)</v>", options: [.dotMatchesLineSeparators])) ?? NSRegularExpression()
    }()
    private static let xlsxInlineTextPattern: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<t[^>]*>(.*?)</t>", options: [.dotMatchesLineSeparators])) ?? NSRegularExpression()
    }()

    private static func parseXLSXSheet(_ data: Data, sharedStrings: [String]) -> String {
        guard let xml = String(data: data, encoding: .utf8) else { return "" }
        var rows: [String] = []
        let range = NSRange(xml.startIndex..., in: xml)
        for rowMatch in xlsxRowPattern.matches(in: xml, range: range) {
            guard let rowRange = Range(rowMatch.range(at: 1), in: xml) else { continue }
            let rowXml = String(xml[rowRange])
            let rowRange2 = NSRange(rowXml.startIndex..., in: rowXml)
            let cells = xlsxCellPattern.matches(in: rowXml, range: rowRange2).compactMap { match -> String? in
                guard match.numberOfRanges > 2,
                      let attrsRange = Range(match.range(at: 1), in: rowXml),
                      let innerRange = Range(match.range(at: 2), in: rowXml) else { return nil }
                let attrs = String(rowXml[attrsRange])
                let inner = String(rowXml[innerRange])
                let rawValue = firstCapture(xlsxValuePattern, in: inner)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                // Shared-string cell: <v> holds an index into sharedStrings.xml.
                if attrs.contains("t=\"s\"") {
                    guard let index = Int(rawValue), sharedStrings.indices.contains(index) else { return nil }
                    return sharedStrings[index]
                }
                // Inline string: text lives in <is><t>…</t></is>.
                if attrs.contains("t=\"inlineStr\"") || attrs.contains("t=\"str\"") {
                    let text = firstCapture(xlsxInlineTextPattern, in: inner)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return text.isEmpty ? nil : text
                }
                return rawValue.isEmpty ? nil : rawValue
            }
            if !cells.isEmpty {
                rows.append(cells.joined(separator: "\t"))
            }
        }
        return rows.joined(separator: "\n")
    }

    /// First capture group of the first match, or nil.
    private static func firstCapture(_ pattern: NSRegularExpression, in text: String) -> String? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
    // MARK: - Test Hooks
    // Exposed for unit tests; the parsing helpers are private otherwise.

    static func parseSharedStringsForTesting(_ data: Data) -> [String] {
        parseSharedStrings(data)
    }

    static func unescapeXMLForTesting(_ text: String) -> String {
        unescapeXML(text)
    }

    static func parseSpreadsheetForTesting(sharedStringsXML: Data, sheetXML: Data) -> String {
        parseXLSXSheet(sheetXML, sharedStrings: parseSharedStrings(sharedStringsXML))
    }
}

nonisolated enum FileExtractorError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case fileTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let name):
            return String(localized: "Could not read file: \(name). Unsupported format.")
        case .fileTooLarge(let name):
            return String(localized: "File too large: \(name). Limit is 5 MB.")
        }
    }
}

nonisolated private struct ZipArchive {
    let data: Data

    /// Cached map of entry path → local header offset — avoids O(n²) traversal for repeated lookups.
    private var entryCache: [String: (offset: Int, compMethod: UInt16, compSize: Int, uncompSize: Int)]?

    init(data: Data) throws {
        self.data = data
    }

    mutating func readEntry(_ path: String) -> Data? {
        // Build cache on first access
        if entryCache == nil {
            entryCache = buildEntryCache()
        }
        guard let cache = entryCache, let entry = cache[path] else { return nil }
        return readLocalFileData(at: entry.offset, compMethod: entry.compMethod, compSize: entry.compSize, uncompSize: entry.uncompSize)
    }

    /// Build a cache of all entries in the central directory.
    /// This is a single O(n) pass instead of O(n) per readEntry call.
    private mutating func buildEntryCache() -> [String: (offset: Int, compMethod: UInt16, compSize: Int, uncompSize: Int)] {
        guard let eocd = findEndOfCentralDirectory() else { return [:] }
        let cdOffset = Int(eocd.centralDirectoryOffset)
        let cdSize = Int(eocd.centralDirectorySize)
        let entryCount = Int(eocd.totalEntries)
        guard cdOffset + cdSize <= data.count else { return [:] }

        var cache: [String: (offset: Int, compMethod: UInt16, compSize: Int, uncompSize: Int)] = [:]
        var offset = cdOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count else { break }
            let signature = data[offset..<offset+4]
            guard signature.elementsEqual([0x50, 0x4B, 0x01, 0x02]) else { break }

            let compMethod = data.readUInt16(offset + 10)
            let compSize = Int(data.readUInt32(offset + 20))
            let uncompSize = Int(data.readUInt32(offset + 24))
            let nameLen = Int(data.readUInt16(offset + 28))
            let extraLen = Int(data.readUInt16(offset + 30))
            let commentLen = Int(data.readUInt16(offset + 32))
            let localHeaderOffset = Int(data.readUInt32(offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLen <= data.count else { break }
            let name = String(data: data[nameStart..<nameStart+nameLen], encoding: .utf8) ?? ""

            cache[name] = (offset: localHeaderOffset, compMethod: compMethod, compSize: compSize, uncompSize: uncompSize)

            offset = nameStart + nameLen + extraLen + commentLen
        }
        return cache
    }

    private func readLocalFileData(at offset: Int, compMethod: UInt16, compSize: Int, uncompSize: Int) -> Data? {
        guard offset >= 0, offset + 30 <= data.count else { return nil }
        let nameLen = Int(data.readUInt16(offset + 26))
        let extraLen = Int(data.readUInt16(offset + 28))
        let dataStart = offset + 30 + nameLen + extraLen
        guard dataStart >= 0, compSize >= 0, dataStart + compSize <= data.count else { return nil }

        let fileData = data[dataStart..<dataStart+compSize]

        if compMethod == 0 {
            return Data(fileData)
        } else if compMethod == 8 {
            return try? (fileData as NSData).decompressed(using: .zlib) as Data
        }
        return nil
    }

    private func findEndOfCentralDirectory() -> (centralDirectoryOffset: UInt32, centralDirectorySize: UInt32, totalEntries: UInt16)? {
        guard data.count >= 22 else { return nil }
        let searchStart = max(0, data.count - 65557)
        for i in stride(from: data.count - 22, through: searchStart, by: -1) {
            guard i + 3 < data.count else { continue }
            if data[i] == 0x50 && data[i+1] == 0x4B && data[i+2] == 0x05 && data[i+3] == 0x06 {
                let totalEntries = data.readUInt16(i + 10)
                let cdSize = data.readUInt32(i + 12)
                let cdOffset = data.readUInt32(i + 16)
                return (cdOffset, cdSize, totalEntries)
            }
        }
        return nil
    }
}

private extension Data {
    nonisolated func readUInt16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 1 < count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset+1]) << 8)
    }

    nonisolated func readUInt32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 3 < count else { return 0 }
        return UInt32(self[offset]) | (UInt32(self[offset+1]) << 8) | (UInt32(self[offset+2]) << 16) | (UInt32(self[offset+3]) << 24)
    }
}
