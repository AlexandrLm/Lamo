import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onRetry: (() -> Void)? = nil

    var body: some View {
        if message.role == .user {
            userMessage
        } else {
            assistantMessage
        }
    }

    // MARK: - User Message

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                if isErrorMessage {
                    errorBubble
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
                if !message.isStreaming {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Assistant Message

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isStreaming && message.content.isEmpty {
                TypingIndicator()
            } else {
                MarkdownRenderer(
                    text: message.content,
                    textColor: .primary
                )
                .lineSpacing(4)
            }
            Spacer(minLength: 48)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Error Bubble

    private var isErrorMessage: Bool {
        message.content.hasPrefix("Ошибка:") || message.content.hasPrefix("Error:")
    }

    @ViewBuilder
    private var errorBubble: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(.systemRed))
                Text("Inference Error")
                    .font(.headline)
                    .foregroundStyle(Color(.systemRed))
            }

            Text(message.content.replacingOccurrences(of: "Ошибка: ", with: "").replacingOccurrences(of: "Error: ", with: ""))
                .font(.subheadline)

            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
