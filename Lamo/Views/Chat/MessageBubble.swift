import SwiftUI

struct MessageBubble: View {
    let message: Message
    let onRetry: (() -> Void)?
    @State private var showCopyConfirmation = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            if message.role == .assistant {
                // Model label
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(ProviderManager.shared.currentModelDisplayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 18)
                .padding(.bottom, 2)
            }

            // Content
            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    userContent
                }
                .padding(.horizontal, 16)
            } else {
                // Assistant: full width, edge to edge
                assistantContent
            }

            // Timestamp + actions
            HStack(spacing: 8) {
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if message.role == .assistant {
                    copyButton
                }
            }
            .padding(.leading, message.role == .user ? 0 : 18)
            .padding(.trailing, message.role == .user ? 16 : 0)
        }
        .messageAppear()
    }

    // MARK: - User Content

    private var userContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundStyle(LamoTheme.Colors.bubbleTextUser)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        LamoTheme.Colors.accent,
                        LamoTheme.Colors.accent.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 4,
                    style: .continuous
                )
            )
            .shadow(color: LamoTheme.Colors.accent.opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - Assistant Content

    private var assistantContent: some View {
        MarkdownRenderer(text: message.content, textColor: LamoTheme.Colors.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var copyButton: some View {
        Button {
            copyContent()
        } label: {
            if showCopyConfirmation {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LamoTheme.Colors.accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .buttonStyle(.plain)
    }

    private func copyContent() {
        let content = message.content
        #if os(iOS)
        UIPasteboard.general.string = content
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showCopyConfirmation = false }
        }
    }
}

// MARK: - Appear Modifier

struct MessageAppearModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func messageAppear() -> some View {
        modifier(MessageAppearModifier())
    }
}
