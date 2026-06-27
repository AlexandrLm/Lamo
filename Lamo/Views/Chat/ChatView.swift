import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isUserNearBottom = true
    @Environment(\.modelContext) private var modelContext
    var onNewChat: (() -> Void)?

    struct PromptSuggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let prompt: String
        let icon: String
    }

    private let suggestions = [
        PromptSuggestion(title: "Explain Concept", subtitle: "Quantum computing in simple words", prompt: "Explain quantum computing in simple terms for a beginner.", icon: "lightbulb.fill"),
        PromptSuggestion(title: "Refine Text", subtitle: "Make an email sound polite", prompt: "Please rewrite this text to make it sound highly professional and polite: [paste text here]", icon: "pencil.and.outline"),
        PromptSuggestion(title: "Code Quickstart", subtitle: "Write a standard Python function", prompt: "Write a clean, documented Python function to calculate the Fibonacci sequence.", icon: "curlybraces")
    ]

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
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: LamoTheme.Spacing.lg) {
                            if viewModel.messages.isEmpty {
                                emptyChatView
                                    .id("empty")
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, onRetry: {
                                    Task {
                                        await viewModel.retryLastMessage()
                                    }
                                })
                                .id(message.id)
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
                        isUserNearBottom = maxY < screenHeight + 150
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

                    if !isUserNearBottom, !viewModel.messages.isEmpty {
                        Button {
                            scrollToBottom(proxy: proxy)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, LamoTheme.Spacing.lg)
                        .padding(.bottom, LamoTheme.Spacing.lg)
                        .transition(.scale.combined(with: .opacity))
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
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onNewChat?()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.tint)
                }
                .sensoryFeedback(.selection, trigger: viewModel.messages.count)
            }
        }
    }

    // MARK: - Empty State

    private var emptyChatView: some View {
        VStack(spacing: LamoTheme.Spacing.xxl) {
            Spacer(minLength: 40)

            VStack(spacing: LamoTheme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular, in: .circle)

                VStack(spacing: LamoTheme.Spacing.sm) {
                    Text("How can I help?")
                        .font(.title2.bold())

                    Text("Powered by offline intelligence")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                Text("Try asking:")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)

                ForEach(suggestions) { suggestion in
                    Button {
                        Task {
                            await viewModel.sendDirect(suggestion.prompt)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: suggestion.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.tint)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .rect(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 400)
            .padding(.top, LamoTheme.Spacing.md)

            Spacer()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
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
