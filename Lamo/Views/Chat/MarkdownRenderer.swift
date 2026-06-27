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
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    let isLast = index == blocks.count - 1
                    Group {
                        switch block {
                        case .code(let code, let language):
                            CodeBlock(code: code, language: language)
                                .padding(.vertical, 4)
                        case .header(let text, let level):
                            HeaderText(text: text, level: level)
                                .padding(.top, level == 1 ? 8 : 4)
                                .padding(.bottom, 2)
                        case .listItem(let text, let indent):
                            ListItemText(text: text, indent: indent)
                                .padding(.leading, CGFloat(indent) * 16)
                                .padding(.vertical, 1)
                        case .text(let content):
                            if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                                RichText(text: content, textColor: textColor)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                    .animation(.easeOut(duration: 0.25), value: blocks.count)
                }

                // Streaming cursor
                if isStreaming {
                    StreamingCursor()
                        .padding(.top, 2)
                        .transition(.opacity)
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

        for line in lines {
            let lineStr = String(line)

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
                continue
            }

            if inCodeBlock {
                codeBuffer.append(lineStr)
                continue
            }

            if lineStr.hasPrefix("### ") {
                blocks.append(.header(String(lineStr.dropFirst(4)), level: 3))
            } else if lineStr.hasPrefix("## ") {
                blocks.append(.header(String(lineStr.dropFirst(3)), level: 2))
            } else if lineStr.hasPrefix("# ") {
                blocks.append(.header(String(lineStr.dropFirst(2)), level: 1))
            } else if lineStr.hasPrefix("- ") || lineStr.hasPrefix("* ") {
                blocks.append(.listItem(String(lineStr.dropFirst(2)), indent: 0))
            } else if lineStr.hasPrefix("  - ") || lineStr.hasPrefix("  * ") {
                blocks.append(.listItem(String(lineStr.dropFirst(4)), indent: 1))
            } else if lineStr.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                let content = lineStr.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                blocks.append(.listItem(content, indent: 0))
            } else if lineStr.trimmingCharacters(in: .whitespaces).isEmpty {
                if let last = blocks.last, case .text(let t) = last, t.trimmingCharacters(in: .whitespaces).isEmpty {
                    // skip consecutive empty lines
                } else {
                    blocks.append(.text(""))
                }
            } else {
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
        case listItem(String, indent: Int)
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

// MARK: - Rich Text

struct RichText: View {
    let text: String
    let textColor: Color

    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
                .font(.body)
                .foregroundStyle(textColor)
                .lineSpacing(4)
        } else {
            Text(text)
                .font(.body)
                .foregroundStyle(textColor)
                .lineSpacing(4)
        }
    }
}

// MARK: - Header Text

struct HeaderText: View {
    let text: String
    let level: Int

    var body: some View {
        Text(text)
            .font(headerFont)
            .foregroundStyle(LamoTheme.Colors.textPrimary)
            .lineSpacing(2)
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

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(LamoTheme.Colors.textTertiary)
                .font(.body)
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
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
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
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.caption2)
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
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }
}
