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
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 16) {
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
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
                    .onTapGesture {
                        hideKeyboard()
                    }
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
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
        .background(LamoTheme.Colors.background)
        .navigationTitle(viewModel.messages.isEmpty ? "" : viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty State (ChatGPT style)

    private var emptyChatView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)

            VStack(spacing: 20) {
                // Logo
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(LamoTheme.Colors.accent)
                    .frame(width: 64, height: 64)
                    .background(LamoTheme.Colors.accent.opacity(0.1), in: Circle())

                // Title
                VStack(spacing: 6) {
                    Text("How can I help you today?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)
                }

                // Suggestion chips
                VStack(spacing: 10) {
                    suggestionRow(
                        icon: "lightbulb",
                        title: "Give me ideas",
                        subtitle: "for a weekend trip"
                    )
                    suggestionRow(
                        icon: "text.alignleft",
                        title: "Help me write",
                        subtitle: "a professional email"
                    )
                    suggestionRow(
                        icon: "brain.head.profile",
                        title: "Explain",
                        subtitle: "how neural networks work"
                    )
                    suggestionRow(
                        icon: "swift",
                        title: "Write code",
                        subtitle: "to sort an array in Swift"
                    )
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    private func suggestionRow(icon: String, title: String, subtitle: String) -> some View {
        Button {
            // TODO: Could pre-fill the input with a suggestion
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LamoTheme.Colors.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textTertiary)
                }

                Spacer()
            }
            .padding(12)
            .background(LamoTheme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Scroll Offset

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
