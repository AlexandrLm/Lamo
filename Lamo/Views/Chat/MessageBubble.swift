import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Assistant Avatar
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(LamoTheme.Colors.accent.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LamoTheme.Colors.accent)
                }
                .padding(.bottom, 20)
            } else {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: LamoTheme.Spacing.xs) {
                if isErrorMessage {
                    errorBubble
                } else {
                    standardBubble
                }

                if !message.isStreaming {
                    Text(message.timestamp, style: .time)
                        .font(LamoTheme.Fonts.caption2)
                        .foregroundStyle(LamoTheme.Colors.textTertiary)
                        .padding(.horizontal, LamoTheme.Spacing.sm)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))

            if message.role == .user {
                // No spacer on the right so user bubble goes to edge
            } else {
                Spacer(minLength: 48)
            }
        }
    }

    private var isErrorMessage: Bool {
        message.content.hasPrefix("Ошибка:") || message.content.hasPrefix("Error:")
    }

    @ViewBuilder
    private var standardBubble: some View {
        if message.isStreaming && message.content.isEmpty {
            TypingIndicator()
                .padding(.horizontal, LamoTheme.Spacing.sm)
                .padding(.vertical, 4)
                .background(bubbleBackground)
                .clipShape(
                    .rect(
                        topLeadingRadius: LamoTheme.CornerRadius.bubble,
                        bottomLeadingRadius: 4,
                        bottomTrailingRadius: LamoTheme.CornerRadius.bubble,
                        topTrailingRadius: LamoTheme.CornerRadius.bubble,
                        style: .continuous
                    )
                )
        } else {
            MarkdownRenderer(
                text: message.content,
                textColor: message.role == .user ? LamoTheme.Colors.bubbleTextUser : LamoTheme.Colors.bubbleTextAssistant
            )
            .lineSpacing(4)
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
            .background(bubbleBackground)
            .clipShape(
                .rect(
                    topLeadingRadius: LamoTheme.CornerRadius.bubble,
                    bottomLeadingRadius: message.role == .user ? LamoTheme.CornerRadius.bubble : 4,
                    bottomTrailingRadius: message.role == .user ? 4 : LamoTheme.CornerRadius.bubble,
                    topTrailingRadius: LamoTheme.CornerRadius.bubble,
                    style: .continuous
                )
            )
            .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private var errorBubble: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LamoTheme.Colors.error)
                Text("Inference Error")
                    .font(LamoTheme.Fonts.headline)
                    .foregroundStyle(LamoTheme.Colors.error)
            }

            Text(message.content.replacingOccurrences(of: "Ошибка: ", with: "").replacingOccurrences(of: "Error: ", with: ""))
                .font(LamoTheme.Fonts.subheadline)
                .foregroundStyle(LamoTheme.Colors.textPrimary)

            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(LamoTheme.Colors.error.opacity(0.1))
                    .foregroundStyle(LamoTheme.Colors.error)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .background(LamoTheme.Colors.error.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.bubble, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.bubble, style: .continuous)
                .stroke(LamoTheme.Colors.error.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            LamoTheme.Colors.userBubble
        } else {
            LamoTheme.Colors.assistantBubble
        }
    }
}
