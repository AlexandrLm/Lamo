import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isUserNearBottom = true
    @Environment(\.modelContext) private var modelContext
    var onNewChat: (() -> Void)?

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        onNewChat: (() -> Void)? = nil
    ) {
        _viewModel = State(wrappedValue: ChatViewModel(conversation: conversation, modelContext: modelContext))
        self.onNewChat = onNewChat
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: LamoTheme.Spacing.md) {
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
                    .padding(.horizontal, LamoTheme.Spacing.md)
                    .padding(.vertical, LamoTheme.Spacing.lg)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .global).maxY
                        )
                    })
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                    let screenHeight = UIScreen.main.bounds.height
                    isUserNearBottom = maxY < screenHeight + 100
                }
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.messages.last?.content) {
                    if isUserNearBottom {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            ChatInputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: { Task { await viewModel.send() } },
                onStop: { viewModel.stopGeneration() }
            )
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle(viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onNewChat?()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }

    private var emptyChatView: some View {
        VStack(spacing: LamoTheme.Spacing.md) {
            Spacer(minLength: 120)
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(LamoTheme.Colors.accent)
                .symbolEffect(.bounce, value: viewModel.messages.isEmpty)
            Text("How can I help you today?")
                .font(.title3.bold())
                .foregroundStyle(LamoTheme.Colors.textPrimary)
            Text("Ask questions, explore ideas, or brainstorm with local intelligence.")
                .font(LamoTheme.Fonts.subheadline)
                .foregroundStyle(LamoTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LamoTheme.Spacing.xl)
            Spacer()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
