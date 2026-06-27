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

        for line in lines {
            let lineStr = String(line)

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
                continue
            }

            if inCodeBlock {
                codeBuffer.append(lineStr)
                continue
            }

            // Horizontal rules
            if lineStr.trimmingCharacters(in: .whitespaces) == "---" ||
               lineStr.trimmingCharacters(in: .whitespaces) == "***" ||
               lineStr.trimmingCharacters(in: .whitespaces) == "___" {
                blocks.append(.hr)
                listCounter = 0
                continue
            }

            // Headers
            if lineStr.hasPrefix("### ") {
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
            // Unordered list items
            else if lineStr.hasPrefix("- ") || lineStr.hasPrefix("* ") {
                let indent = 0
                let content = String(lineStr.dropFirst(2))
                blocks.append(.listItem(content, indent: indent, number: nil))
                listCounter = 0
            } else if lineStr.hasPrefix("  - ") || lineStr.hasPrefix("  * ") {
                let content = String(lineStr.dropFirst(4))
                blocks.append(.listItem(content, indent: 1, number: nil))
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
        }

        if inCodeBlock {
            blocks.append(.code(code: codeBuffer.joined(separator: "\n"), language: language))
        }

        return blocks
    }

    private enum Block {
        case text(String)
        case code(code: String, language: String)
        case header(String, level: Int)
        case listItem(String, indent: Int, number: Int?)
        case blockquote(String)
        case hr
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
        default: return .headline.bold()
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
                Text("•")
                    .font(.body)
                    .foregroundStyle(LamoTheme.Colors.accent)
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
