import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    var onToggleSidebar: (() -> Void)?
    var onNewChat: (() -> Void)?

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        onToggleSidebar: (() -> Void)? = nil,
        onNewChat: (() -> Void)? = nil
    ) {
        _viewModel = State(wrappedValue: ChatViewModel(conversation: conversation, modelContext: modelContext))
        self.onToggleSidebar = onToggleSidebar
        self.onNewChat = onNewChat
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: LamoTheme.Spacing.sm) {
                        if viewModel.messages.isEmpty {
                            emptyChatView
                                .id("empty")
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming, let last = viewModel.messages.last, last.role == .assistant, last.content.isEmpty {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(LamoTheme.Spacing.md)
                }
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.messages.last?.content) {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            ChatInputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: { Task { await viewModel.send() } },
                onStop: { viewModel.stopGeneration() }
            )
        }
        .background(LamoTheme.Colors.background)
    }

    private var headerBar: some View {
        HStack {
            Button {
                onToggleSidebar?()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(viewModel.conversationTitle)
                .font(LamoTheme.Fonts.headline)
                .lineLimit(1)

            Spacer()

            Button {
                onNewChat?()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LamoTheme.Spacing.md)
        .padding(.vertical, LamoTheme.Spacing.sm)
    }

    private var emptyChatView: some View {
        VStack(spacing: LamoTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(LamoTheme.Colors.textSecondary)
            Text("How can I help you?")
                .font(.title2)
                .foregroundStyle(LamoTheme.Colors.textSecondary)
            Spacer()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
