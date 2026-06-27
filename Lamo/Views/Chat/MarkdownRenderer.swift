import SwiftUI

struct MarkdownRenderer: View {
    let text: String
    let textColor: Color

    var body: some View {
        if text.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .code(let code, let language):
                        CodeBlock(code: code, language: language)
                    case .text(let content):
                        StyledText(content)
                            .font(LamoTheme.Fonts.body)
                            .foregroundStyle(textColor)
                            .lineSpacing(4)
                    }
                }
            }
        }
    }

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
            } else if inCodeBlock {
                codeBuffer.append(lineStr)
            } else {
                blocks.append(.text(lineStr))
            }
        }

        if inCodeBlock {
            blocks.append(.code(code: codeBuffer.joined(separator: "\n"), language: language))
        }

        return blocks
    }

    private func StyledText(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        } else {
            return Text(text)
        }
    }

    private enum Block {
        case text(String)
        case code(code: String, language: String)
    }
}

// MARK: - Code Block

struct CodeBlock: View {
    let code: String
    let language: String
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.xs) {
            HStack {
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .bold()
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
                            .font(.caption2)
                    }
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(LamoTheme.Fonts.codeBlock)
                    .textSelection(.enabled)
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
            }
        }
        .padding(LamoTheme.Spacing.md)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.md, style: .continuous))
    }
}
