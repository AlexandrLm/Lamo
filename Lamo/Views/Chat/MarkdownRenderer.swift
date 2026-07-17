import SwiftUI

/// Renders markdown text in chat bubbles.
/// Hybrid approach: simple block-level parsing for structure (headers, lists,
/// blockquotes, code blocks, tables) + native AttributedString(markdown:) for
/// inline formatting (bold, italic, code spans, links).
struct MarkdownRenderer: View {
    let text: String
    let textColor: Color
    let isStreaming: Bool
    /// Cached parsed blocks — only recomputed when `text` actually changes.
    /// During streaming, `isStreaming` toggles don't trigger a re-parse.
    private let cachedBlocks: [Block]

    init(text: String, textColor: Color, isStreaming: Bool = false) {
        self.text = text
        self.textColor = textColor
        self.isStreaming = isStreaming
        self.cachedBlocks = Self.parseBlocksCached(text)
    }

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            MarkdownBody(blocks: cachedBlocks, textColor: textColor, isStreaming: isStreaming)
        }
    }

    /// Parse blocks once per unique text, cached statically for the session.
    /// Avoids re-parsing on every SwiftUI body evaluation during streaming.
    private static func parseBlocksCached(_ text: String) -> [Block] {
        if let cached = blockCache.object(forKey: text as NSString) {
            return cached.blocks
        }
        let blocks = parseBlocksStatic(text)
        let cost = text.utf8.count
        blockCache.setObject(CacheValue(blocks), forKey: text as NSString, cost: cost)
        return blocks
    }

    /// Type-safe NSCache wrapper — avoids unsafe bridging of Swift enums to NSArray.
    private static let blockCache: NSCache<NSString, CacheValue> = {
        let cache = NSCache<NSString, CacheValue>()
        cache.countLimit = 50      // max 50 messages cached
        cache.totalCostLimit = 2 * 1024 * 1024  // 2MB
        return cache
    }()

    /// Thin wrapper so NSCache stores a known type instead of NSArray + force-cast.
    private final class CacheValue {
        let blocks: [Block]
        init(_ blocks: [Block]) { self.blocks = blocks }
    }

    // MARK: - Body (extracted to minimize re-render scope)

    private struct MarkdownBody: View {
        let blocks: [Block]
        let textColor: Color
        let isStreaming: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .code(let code, let language):
                        CodeBlock(code: code, language: language)
                            .padding(.vertical, 8)
                    case .header(let text, let level):
                        VStack(alignment: .leading, spacing: 4) {
                            InlineMarkdown(text: text, textColor: textColor, font: headerFont(level))
                            if level <= 2 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 0.5)
                            }
                        }
                        .padding(.top, level == 1 ? 16 : (level == 2 ? 14 : 10))
                        .padding(.bottom, level <= 2 ? 6 : 4)
                    case .listItem(let text, let indent, let number):
                        HStack(alignment: .top, spacing: 8) {
                            if let number {
                                Text("\(number).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                            } else {
                                Text(bulletForIndent(indent))
                                    .font(.system(size: 10))
                                    .foregroundStyle(indent == 0 ? .white.opacity(0.5) : .white.opacity(0.3))
                                    .frame(width: 18, alignment: .center)
                                    .padding(.top, 4)
                            }
                            InlineMarkdown(text: text, textColor: textColor)
                        }
                        .padding(.leading, CGFloat(indent) * 18)
                        .padding(.vertical, 2)
                    case .taskItem(let text, let checked):
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline)
                                .foregroundStyle(checked ? .white.opacity(0.5) : .secondary)
                                .frame(width: 18, alignment: .center)
                            InlineMarkdown(text: text, textColor: textColor)
                                .foregroundStyle(checked ? .secondary : textColor)
                                .strikethrough(checked)
                        }
                        .padding(.leading, 4)
                        .padding(.vertical, 2)
                    case .blockquote(let text):
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 2.5)
                            InlineMarkdown(text: text, textColor: textColor)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .padding(.leading, 4)
                        .padding(.vertical, 4)
                    case .hr:
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.vertical, 12)
                    case .table(let headers, let rows):
                        MarkdownTable(headers: headers, rows: rows)
                            .padding(.vertical, 8)
                    case .text(let content):
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            InlineMarkdown(text: content, textColor: textColor)
                                .padding(.bottom, 6)
                        }
                    }
                }

                if isStreaming {
                    StreamingCursor()
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Block Types

    private enum Block: Sendable {
        case text(String)
        case code(code: String, language: String)
        case header(String, level: Int)
        case listItem(String, indent: Int, number: Int?)
        case taskItem(String, checked: Bool)
        case blockquote(String)
        case hr
        case table(headers: [String], rows: [[String]])
    }

    // MARK: - Block Parsing

    /// Cached regex for ordered list detection.
    /// Cached regex for ordered list detection.
    private static let orderedListPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\d+\.\s"#)
    }()

    private static func parseBlocksStatic(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var inCodeBlock = false
        var codeBuffer: [String] = []
        var language = ""
        var listCounter = 0
        var textBuffer: [String] = []

        func flushText() {
            if !textBuffer.isEmpty {
                let merged = textBuffer.joined(separator: "\n")
                if !merged.trimmingCharacters(in: .whitespaces).isEmpty {
                    blocks.append(.text(merged))
                }
                textBuffer.removeAll()
            }
        }

        var i = 0
        while i < lines.count {
            let line = String(lines[i])

            if line.hasPrefix("```") {
                flushText()
                if inCodeBlock {
                    blocks.append(.code(code: codeBuffer.joined(separator: "\n"), language: language))
                    codeBuffer = []
                    language = ""
                    inCodeBlock = false
                } else {
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                listCounter = 0
                i += 1
                continue
            }

            if inCodeBlock {
                codeBuffer.append(line)
                i += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushText()
                blocks.append(.hr)
                listCounter = 0
                i += 1
                continue
            }

            if i + 1 < lines.count,
               line.contains("|"),
               let headerRow = parseTableRow(line),
               isTableSeparatorRow(String(lines[i + 1])) {
                flushText()
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count {
                    if let parsed = parseTableRow(String(lines[j])) {
                        rows.append(parsed)
                        j += 1
                    } else { break }
                }
                blocks.append(.table(headers: headerRow, rows: rows))
                listCounter = 0
                i = j
                continue
            }

            if line.hasPrefix("###### ") {
                flushText()
                blocks.append(.header(String(line.dropFirst(7)), level: 6))
                listCounter = 0
            } else if line.hasPrefix("##### ") {
                flushText()
                blocks.append(.header(String(line.dropFirst(6)), level: 5))
                listCounter = 0
            } else if line.hasPrefix("#### ") {
                flushText()
                blocks.append(.header(String(line.dropFirst(5)), level: 4))
                listCounter = 0
            } else if line.hasPrefix("### ") {
                flushText()
                blocks.append(.header(String(line.dropFirst(4)), level: 3))
                listCounter = 0
            } else if line.hasPrefix("## ") {
                flushText()
                blocks.append(.header(String(line.dropFirst(3)), level: 2))
                listCounter = 0
            } else if line.hasPrefix("# ") {
                flushText()
                blocks.append(.header(String(line.dropFirst(2)), level: 1))
                listCounter = 0
            }
            else if line.hasPrefix("> ") {
                flushText()
                blocks.append(.blockquote(String(line.dropFirst(2))))
                listCounter = 0
            }
            else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                flushText()
                blocks.append(.taskItem(String(line.dropFirst(6)), checked: line.hasPrefix("- [x] ")))
                listCounter = 0
            }
            else if line.hasPrefix("    - ") || line.hasPrefix("    * ") {
                flushText()
                blocks.append(.listItem(String(line.dropFirst(6)), indent: 2, number: nil))
                listCounter = 0
            } else if line.hasPrefix("  - ") || line.hasPrefix("  * ") {
                flushText()
                blocks.append(.listItem(String(line.dropFirst(4)), indent: 1, number: nil))
                listCounter = 0
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushText()
                blocks.append(.listItem(String(line.dropFirst(2)), indent: 0, number: nil))
                listCounter = 0
            }
            else if orderedListPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                flushText()
                let content = line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                listCounter += 1
                blocks.append(.listItem(content, indent: 0, number: listCounter))
            }
            else if trimmed.isEmpty {
                flushText()
                listCounter = 0
            }
            else {
                textBuffer.append(line)
            }

            i += 1
        }

        if inCodeBlock {
            blocks.append(.code(code: codeBuffer.joined(separator: "\n"), language: language))
        }
        flushText()
        return blocks
    }

    // MARK: - Helpers

    private static func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.bold()
        case 2: return .headline.bold()
        case 3: return .subheadline.bold()
        case 4: return .footnote.bold()
        case 5: return .caption.bold()
        default: return .caption2.bold()
        }
    }

    private static func bulletForIndent(_ indent: Int) -> String {
        switch indent {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }

    // MARK: - Table Helpers

    private static func parseTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparatorRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }
        let inner = String(trimmed.dropFirst().dropLast())
        let parts = inner.split(separator: "|")
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            return trimmed.allSatisfy { $0 == "-" || $0 == ":" }
                && trimmed.contains("-")
        }
    }
}

// MARK: - Inline Markdown (native AttributedString)

/// Renders a single block of text with inline markdown formatting
/// (bold, italic, code spans, links) using SwiftUI's native parser.
private struct InlineMarkdown: View {
    let text: String
    let textColor: Color
    var font: Font = .subheadline

    var body: some View {
        if let attributed = formatInlineMarkdown(text) {
            Text(attributed)
                .font(font)
                .foregroundStyle(textColor)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(textColor)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    private func formatInlineMarkdown(_ text: String) -> AttributedString? {
        // First try native markdown parsing
        guard var attributed = try? AttributedString(markdown: text) else { return nil }

        // Style inline code spans and links
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                attributed[run.range].backgroundColor = Color.white.opacity(0.06)
                attributed[run.range].font = .system(.footnote, design: .monospaced)
                attributed[run.range].foregroundColor = .white.opacity(0.8)
            }
            if run.link != nil {
                attributed[run.range].foregroundColor = .white.opacity(0.7)
                attributed[run.range].underlineStyle = .single
            }
        }
        return attributed
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white.opacity(0.5))
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - Code Block

struct CodeBlock: View {
    let code: String
    let language: String
    @State private var isCopied = false
    @State private var copyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copyTask?.cancel()
                    withAnimation { isCopied = true }
                    copyTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        withAnimation { isCopied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(isCopied ? .white.opacity(0.6) : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .glassEffect(.regular.tint(Color.white.opacity(0.03)), in: .rect(cornerRadius: 10))
    }
}

// MARK: - Markdown Table

struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { col in
                        let text = col < headers.count ? headers[col] : ""
                        MarkdownTableCell(text: text, isHeader: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .gridColumnAlignment(col == 0 ? .leading : .leading)
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { col in
                            let cell = col < row.count ? row[col] : ""
                            MarkdownTableCell(text: cell, isHeader: false)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                        }
                    }
                    .background(
                        rowIndex % 2 == 0
                            ? Color.clear
                            : Color.white.opacity(0.02)
                    )

                    if rowIndex < rows.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(height: 0.5)
                            .padding(.horizontal, 10)
                    }
                }
            }
            .frame(minWidth: 280)
        }
        .glassEffect(.regular.tint(Color.white.opacity(0.03)), in: .rect(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Table Cell

private struct MarkdownTableCell: View {
    let text: String
    let isHeader: Bool

    var body: some View {
        Group {
            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(isHeader ? .footnote.weight(.semibold) : .footnote)
        .foregroundStyle(isHeader ? .white.opacity(0.8) : LamoTheme.Colors.textPrimary.opacity(0.85))
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 44, alignment: .leading)
        .textSelection(.enabled)
    }
}
