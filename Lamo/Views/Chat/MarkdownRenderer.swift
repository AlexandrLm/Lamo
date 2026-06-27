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

struct CodeBlock: View {
    let code: String
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.xs) {
            if !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .bold()
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(LamoTheme.Fonts.code)
                    .textSelection(.enabled)
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
            }
        }
        .padding(LamoTheme.Spacing.md)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        )
    }
}
