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
            VStack(alignment: .trailing, spacing: 3) {
                if isErrorMessage {
                    errorBubble
                } else {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(LamoTheme.Colors.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    // MARK: - Assistant Message

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 0) {
            if message.isStreaming && message.content.isEmpty {
                TypingIndicator()
            } else {
                MarkdownRenderer(
                    text: message.content,
                    textColor: LamoTheme.Colors.textPrimary,
                    isStreaming: message.isStreaming
                )
            }

            if !message.isStreaming && !message.content.isEmpty {
                HStack(spacing: 14) {
                    Button {
                        UIPasteboard.general.string = message.content
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)

                    if let onRetry {
                        Button(action: onRetry) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Error Bubble

    private var isErrorMessage: Bool {
        message.content.hasPrefix("Ошибка:") || message.content.hasPrefix("Error:")
    }

    @ViewBuilder
    private var errorBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(.systemRed))
                Text("Inference Error")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.systemRed))
            }

            Text(message.content.replacingOccurrences(of: "Ошибка: ", with: "").replacingOccurrences(of: "Error: ", with: ""))
                .font(.subheadline)

            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Retry")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
