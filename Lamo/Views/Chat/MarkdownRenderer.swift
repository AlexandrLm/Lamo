import SwiftUI

struct MarkdownRenderer: View {
    let text: String

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
        let attributed = parseInlineFormatting(text)
        return Text(attributed)
    }

    private func parseInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        let boldPattern = /\*\*(.+?)\*\*/
        for match in text.matches(of: boldPattern) {
            let matchStr = String(match.output.0)
            if let range = result.range(of: matchStr) {
                result[range].font = .body.bold()
            }
        }

        let italicPattern = /\*(.+?)\*/
        for match in text.matches(of: italicPattern) {
            let matchStr = String(match.output.0)
            if let range = result.range(of: matchStr) {
                result[range].font = .body.italic()
            }
        }

        let inlineCodePattern = /`(.+?)`/
        for match in text.matches(of: inlineCodePattern) {
            let matchStr = String(match.output.0)
            if let range = result.range(of: matchStr) {
                result[range].font = LamoTheme.Fonts.code
                result[range].foregroundColor = .orange
            }
        }

        return result
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
                Text(language)
                    .font(LamoTheme.Fonts.caption)
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(LamoTheme.Fonts.code)
                    .textSelection(.enabled)
            }
        }
        .padding(LamoTheme.Spacing.md)
        .background(LamoTheme.Colors.assistantBubble)
        .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.bubble))
    }
}
