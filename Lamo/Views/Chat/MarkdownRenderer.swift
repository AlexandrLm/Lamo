import SwiftUI

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
                        HeaderText(text: text, level: level)
                            .padding(.top, level == 1 ? 12 : level == 2 ? 8 : 6)
                            .padding(.bottom, 4)
                    case .listItem(let text, let indent, let number):
                        ListItemText(text: text, indent: indent, number: number)
                            .padding(.leading, CGFloat(indent) * 20)
                            .padding(.vertical, 2)
                    case .blockquote(let text):
                        BlockquoteText(text: text)
                            .padding(.vertical, 4)
                    case .hr:
                        Divider()
                            .padding(.vertical, 12)
                            .overlay(Color(.separator).opacity(0.3))
                    case .table(let headers, let rows):
                        MarkdownTable(headers: headers, rows: rows)
                            .padding(.vertical, 6)
                    case .text(let content):
                        if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                            RichText(text: content, textColor: textColor)
                                .padding(.bottom, 6)
                        }
                    }
                }

                if isStreaming {
                    StreamingCursor()
                        .padding(.top, 4)
                }
            }
            .textSelection(.enabled)
        }
    }

    // MARK: - Block Parsing

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var inCodeBlock = false
        var codeBuffer: [String] = []
        var language = ""
        var listCounter = 0

        var i = 0
        while i < lines.count {
            let lineStr = String(lines[i])

            // Code block toggle
            if lineStr.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.code(code: codeBuffer.joined(separator: "\n"), language: language))
                    codeBuffer = []
                    language = ""
                    inCodeBlock = false
                } else {
                    language = String(lineStr.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
                listCounter = 0
                i += 1
                continue
            }

            if inCodeBlock {
                codeBuffer.append(lineStr)
                i += 1
                continue
            }

            // Horizontal rules
            if lineStr.trimmingCharacters(in: .whitespaces) == "---" ||
               lineStr.trimmingCharacters(in: .whitespaces) == "***" ||
               lineStr.trimmingCharacters(in: .whitespaces) == "___" {
                blocks.append(.hr)
                listCounter = 0
                i += 1
                continue
            }

            // Table detection: header row with pipes, followed by separator row
            if i + 1 < lines.count,
               lineStr.contains("|"),
               let headerRow = parseTableRow(lineStr) {
                let nextLine = String(lines[i + 1])
                if isTableSeparatorRow(nextLine) {
                    let headers = headerRow
                    var rows: [[String]] = []
                    var j = i + 2
                    while j < lines.count {
                        let rowLine = String(lines[j])
                        if let parsed = parseTableRow(rowLine) {
                            rows.append(parsed)
                            j += 1
                        } else {
                            break
                        }
                    }
                    blocks.append(.table(headers: headers, rows: rows))
                    listCounter = 0
                    i = j
                    continue
                }
            }

            // Headers — match longest prefix first (###### before ###)
            if lineStr.hasPrefix("###### ") {
                blocks.append(.header(String(lineStr.dropFirst(7)), level: 6))
                listCounter = 0
            } else if lineStr.hasPrefix("##### ") {
                blocks.append(.header(String(lineStr.dropFirst(6)), level: 5))
                listCounter = 0
            } else if lineStr.hasPrefix("#### ") {
                blocks.append(.header(String(lineStr.dropFirst(5)), level: 4))
                listCounter = 0
            } else if lineStr.hasPrefix("### ") {
                blocks.append(.header(String(lineStr.dropFirst(4)), level: 3))
                listCounter = 0
            } else if lineStr.hasPrefix("## ") {
                blocks.append(.header(String(lineStr.dropFirst(3)), level: 2))
                listCounter = 0
            } else if lineStr.hasPrefix("# ") {
                blocks.append(.header(String(lineStr.dropFirst(2)), level: 1))
                listCounter = 0
            }
            // Blockquotes
            else if lineStr.hasPrefix("> ") {
                let content = String(lineStr.dropFirst(2))
                blocks.append(.blockquote(content))
                listCounter = 0
            }
            // Unordered list items — support 3 indent levels
            else if lineStr.hasPrefix("- ") || lineStr.hasPrefix("* ") {
                let content = String(lineStr.dropFirst(2))
                blocks.append(.listItem(content, indent: 0, number: nil))
                listCounter = 0
            } else if lineStr.hasPrefix("  - ") || lineStr.hasPrefix("  * ") {
                let content = String(lineStr.dropFirst(4))
                blocks.append(.listItem(content, indent: 1, number: nil))
                listCounter = 0
            } else if lineStr.hasPrefix("    - ") || lineStr.hasPrefix("    * ") {
                let content = String(lineStr.dropFirst(6))
                blocks.append(.listItem(content, indent: 2, number: nil))
                listCounter = 0
            }
            // Ordered list items
            else if lineStr.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                let content = lineStr.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                listCounter += 1
                blocks.append(.listItem(content, indent: 0, number: listCounter))
            }
            // Empty lines — skip consecutive, reset list counter
            else if lineStr.trimmingCharacters(in: .whitespaces).isEmpty {
                listCounter = 0
                if let last = blocks.last, case .text(let t) = last, t.trimmingCharacters(in: .whitespaces).isEmpty {
                    // skip consecutive empty lines
                } else {
                    blocks.append(.text(""))
                }
            }
            // Regular text
            else {
                blocks.append(.text(lineStr))
            }

            i += 1
        }

        if inCodeBlock {
            blocks.append(.code(code: codeBuffer.joined(separator: "\n"), language: language))
        }

        return blocks
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
                && trimmed.filter({ $0 == "-" }).count > 0
        }
    }

    private enum Block {
        case text(String)
        case code(code: String, language: String)
        case header(String, level: Int)
        case listItem(String, indent: Int, number: Int?)
        case blockquote(String)
        case hr
        case table(headers: [String], rows: [[String]])
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var visible = true
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(LamoTheme.Colors.accent)
            .frame(width: 8, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - Rich Text (Inline Markdown)

struct RichText: View {
    let text: String
    let textColor: Color

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.body)
                .foregroundStyle(textColor)
                .lineSpacing(5)
        } else {
            Text(text)
                .font(.body)
                .foregroundStyle(textColor)
                .lineSpacing(5)
        }
    }
}

// MARK: - Header Text

struct HeaderText: View {
    let text: String
    let level: Int
    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(headerFont)
                .foregroundStyle(LamoTheme.Colors.textPrimary)
        } else {
            Text(text)
                .font(headerFont)
                .foregroundStyle(LamoTheme.Colors.textPrimary)
        }
    }

    private var headerFont: Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline.bold()
        case 4: return .subheadline.bold()
        case 5: return .caption.bold()
        default: return .caption.bold()
        }
    }
}

// MARK: - List Item

struct ListItemText: View {
    let text: String
    let indent: Int
    let number: Int?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let number {
                Text("\(number).")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
            } else {
                Text(indent == 0 ? "•" : "◦")
                    .font(.body)
                    .foregroundStyle(indent == 0 ? LamoTheme.Colors.accent : LamoTheme.Colors.accent.opacity(0.6))
                    .frame(width: 20, alignment: .center)
            }

            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
                    .font(.body)
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
                    .lineSpacing(3)
            } else {
                Text(text)
                    .font(.body)
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - Blockquote

struct BlockquoteText: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(LamoTheme.Colors.accent.opacity(0.5))
                .frame(width: 3)

            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .italic()
            } else {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .italic()
            }
        }
        .padding(.leading, 4)
    }
}

// MARK: - Code Block

struct CodeBlock: View {
    let code: String
    let language: String
    @State private var isCopied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                    withAnimation {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isCopied = false
                        }
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.quaternarySystemFill))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cellText(header, isHeader: true)
                            .frame(minWidth: 60, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(LamoTheme.Colors.accent.opacity(0.12))

                // Separator line
                Rectangle()
                    .fill(LamoTheme.Colors.accent.opacity(0.3))
                    .frame(height: 1)

                // Data rows with alternating background
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(0..<max(headers.count, row.count), id: \.self) { colIndex in
                            let cell = colIndex < row.count ? row[colIndex] : ""
                            cellText(cell, isHeader: false)
                                .frame(minWidth: 60, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(rowIndex % 2 == 0
                        ? Color.clear
                        : Color(.tertiarySystemFill).opacity(0.3))

                    if rowIndex < rows.count - 1 {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.2))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func cellText(_ text: String, isHeader: Bool) -> some View {
        Group {
            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
        .foregroundStyle(isHeader ? LamoTheme.Colors.textPrimary : LamoTheme.Colors.textPrimary.opacity(0.85))
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.trailing, 12)
    }
}
