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
                    LazyVStack(spacing: LamoTheme.Spacing.lg) {
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
                    .frame(maxWidth: LamoTheme.maxContentWidth)
                    .padding(.horizontal, LamoTheme.Spacing.lg)
                    .padding(.vertical, LamoTheme.Spacing.xl)
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
                .scrollDismissesKeyboard(.interactively)
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onNewChat?()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.accent)
                }
                .sensoryFeedback(.selection, trigger: viewModel.messages.count)
            }
        }
    }

    // MARK: - Empty State (Claude-style)

    private var emptyChatView: some View {
        VStack(spacing: LamoTheme.Spacing.xxl) {
            Spacer(minLength: 80)

            VStack(spacing: LamoTheme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(LamoTheme.Colors.accent)

                VStack(spacing: LamoTheme.Spacing.sm) {
                    Text("How can I help?")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)

                    Text("Powered by local intelligence")
                        .font(.subheadline)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
            }

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

// MARK: - Scroll Offset

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
