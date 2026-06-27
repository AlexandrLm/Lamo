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

    // MARK: - Empty State

    private var emptyChatView: some View {
        VStack(spacing: LamoTheme.Spacing.xl) {
            Spacer(minLength: 80)

            ZStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 150, height: 150)
                    .blur(radius: 40)
                    .opacity(0.3)

                Circle()
                    .fill(.purple)
                    .frame(width: 150, height: 150)
                    .offset(x: 40, y: 40)
                    .blur(radius: 40)
                    .opacity(0.3)

                Image(systemName: "sparkles")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }

            VStack(spacing: 8) {
                Text("How can I help?")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(LamoTheme.Colors.textPrimary)

                Text("Powered by local intelligence")
                    .font(.subheadline)
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
            }

            VStack(spacing: 12) {
                SuggestionChip(text: "Summarize a complex topic", icon: "doc.text.magnifyingglass")
                SuggestionChip(text: "Write a Swift function", icon: "chevron.left.forwardslash.chevron.right")
                SuggestionChip(text: "Help me debug my code", icon: "ladybug")
            }
            .padding(.top, 24)

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

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    var icon: String = "sparkle"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(LamoTheme.Colors.accent)
                .font(.subheadline)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LamoTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemFill))
        .clipShape(Capsule())
    }
}

// MARK: - Scroll Offset

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
