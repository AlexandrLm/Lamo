import SwiftUI

/// Renders markdown text in chat bubbles.
/// Hybrid approach: simple block-level parsing for structure (headers, lists,
/// blockquotes, code blocks, tables) + native AttributedString(markdown:) for
/// inline formatting (bold, italic, code spans, links).
struct MarkdownRenderer: View {
    let text: String
    let textColor: Color
    let isStreaming: Bool

    init(text: String, textColor: Color, isStreaming: Bool = false) {
        self.text = text
        self.textColor = textColor
        self.isStreaming = isStreaming
    }

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                let blocks = parseBlocks()
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .code(let code, let language):
                        CodeBlock(code: code, language: language)
                            .padding(.vertical, 6)
                    case .header(let text, let level):
                        InlineMarkdown(text: text, textColor: textColor, font: headerFont(level))
                            .padding(.top, level <= 2 ? 10 : 6)
                            .padding(.bottom, 3)
                    case .listItem(let text, let indent, let number):
                        HStack(alignment: .top, spacing: 6) {
                            if let number {
                                Text("\(number).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                            } else {
                                Text(bulletForIndent(indent))
                                    .font(.subheadline)
                                    .foregroundStyle(indent == 0 ? LamoTheme.Colors.accent : LamoTheme.Colors.accent.opacity(0.5))
                                    .frame(width: 18, alignment: .center)
                            }
                            InlineMarkdown(text: text, textColor: textColor)
                        }
                        .padding(.leading, CGFloat(indent) * 18)
                        .padding(.vertical, 1)
                    case .taskItem(let text, let checked):
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline)
                                .foregroundStyle(checked ? LamoTheme.Colors.accent : .secondary)
                                .frame(width: 18, alignment: .center)
                            InlineMarkdown(text: text, textColor: textColor)
                                .foregroundStyle(checked ? .secondary : textColor)
                                .strikethrough(checked)
                        }
                        .padding(.leading, 4)
                        .padding(.vertical, 1)
                    case .blockquote(let text):
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(LamoTheme.Colors.accent.opacity(0.4))
                                .frame(width: 3)
                            InlineMarkdown(text: text, textColor: textColor)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .padding(.leading, 4)
                        .padding(.vertical, 3)
                    case .hr:
                        Divider()
                            .padding(.vertical, 10)
                            .overlay(Color(.separator).opacity(0.3))
                    case .table(let headers, let rows):
                        MarkdownTable(headers: headers, rows: rows)
                            .padding(.vertical, 6)
                    case .text(let content):
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            InlineMarkdown(text: content, textColor: textColor)
                                .padding(.bottom, 4)
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

    private enum Block {
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

    private func parseBlocks() -> [Block] {
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

            // Code block
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

            // HR
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushText()
                blocks.append(.hr)
                listCounter = 0
                i += 1
                continue
            }

            // Table
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

            // Headers (###### first to match longest prefix)
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
            // Blockquote
            else if line.hasPrefix("> ") {
                flushText()
                blocks.append(.blockquote(String(line.dropFirst(2))))
                listCounter = 0
            }
            // Task list
            else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                flushText()
                blocks.append(.taskItem(String(line.dropFirst(6)), checked: line.hasPrefix("- [x] ")))
                listCounter = 0
            }
            // Unordered list (3 indent levels)
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
            // Ordered list
            else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                flushText()
                let content = line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                listCounter += 1
                blocks.append(.listItem(content, indent: 0, number: listCounter))
            }
            // Empty line
            else if trimmed.isEmpty {
                flushText()
                listCounter = 0
            }
            // Text
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

    private func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline.bold()
        case 4: return .subheadline.bold()
        case 5: return .footnote.bold()
        default: return .caption.bold()
        }
    }

    private func bulletForIndent(_ indent: Int) -> String {
        switch indent {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }

    // MARK: - Table Helpers

    private func parseTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }
        let inner = String(trimmed.dropFirst().dropLast())
        return inner.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func isTableSeparatorRow(_ line: String) -> Bool {
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
        if let attributed = try? AttributedString(markdown: text) {
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
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(LamoTheme.Colors.accent)
            .frame(width: 8, height: 14)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(LamoTheme.Colors.accent)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation { isCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { isCopied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.quaternarySystemFill))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Markdown Table

struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        TableCellText(text: header)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LamoTheme.Colors.textPrimary)
                            .padding(.trailing, 14)
                    }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(
                    LinearGradient(
                        colors: [
                            LamoTheme.Colors.accent.opacity(0.1),
                            LamoTheme.Colors.accent.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                // Accent separator
                Rectangle()
                    .fill(LamoTheme.Colors.accent.opacity(0.3))
                    .frame(height: 1.5)

                // Rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(0..<max(headers.count, row.count), id: \.self) { colIndex in
                            let cell = colIndex < row.count ? row[colIndex] : ""
                            TableCellText(text: cell)
                                .font(.subheadline)
                                .foregroundStyle(LamoTheme.Colors.textPrimary.opacity(0.8))
                                .padding(.trailing, 14)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(rowIndex % 2 == 1
                        ? Color(.tertiarySystemFill).opacity(0.2)
                        : Color.clear)

                    if rowIndex < rows.count - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.15))
                            .frame(height: 0.5)
                            .padding(.horizontal, 6)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            LamoTheme.Colors.accent.opacity(0.2),
                            Color(.separator).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Table Cell

private struct TableCellText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 50, alignment: .leading)
        } else {
            Text(text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 50, alignment: .leading)
        }
    }
}
